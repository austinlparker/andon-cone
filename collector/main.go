package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	_ "modernc.org/sqlite"
)

const (
	defaultMetadataURL = "https://os.andonlabs.com/api/public/radio/metadata"
	defaultStatsURL    = "https://os.andonlabs.com/api/public/radio/stats"
	defaultDBPath      = "andon-history.sqlite3"
)

var knownStations = map[string]StationSeed{
	"aab4d149-92fa-4386-9c1e-d938ecb66ee3": {
		Name:      "Backlink Broadcast",
		Host:      "Gemini 3.1 Pro Preview",
		StreamURL: "https://streaming.live365.com/a13541",
	},
	"6b53fc38-ed57-4738-80d6-f9fddf981054": {
		Name:      "Thinking Frequencies",
		Host:      "Claude Opus 4.7",
		StreamURL: "https://streaming.live365.com/a46431",
	},
	"df197c3e-0137-4665-95f3-0fc5cec1ee1e": {
		Name:      "OpenAIR",
		Host:      "GPT 5.5",
		StreamURL: "https://streaming.live365.com/a81044",
	},
	"887ec509-2be8-433e-a27e-d05c1dc21278": {
		Name:      "Grok and Roll",
		Host:      "Grok 4.3",
		StreamURL: "https://streaming.live365.com/a15419",
	},
}

type Config struct {
	MetadataURL string
	StatsURL    string
	DBPath      string
	Interval    time.Duration
	Once        bool
}

type StationSeed struct {
	Name      string
	Host      string
	StreamURL string
}

type MetadataResponse struct {
	Stations map[string]TrackMetadata `json:"stations"`
}

type TrackMetadata struct {
	Title  string `json:"title"`
	Artist string `json:"artist"`
	Online bool   `json:"online"`
	Error  string `json:"error"`
}

type StatsResponse struct {
	Stations []StationStats `json:"stations"`
}

type StationStats struct {
	ID           string       `json:"id"`
	Name         string       `json:"name"`
	Subtitle     string       `json:"subtitle"`
	StationID    string       `json:"stationId"`
	StreamURL    string       `json:"streamUrl"`
	ImageURL     string       `json:"imageUrl"`
	PrimaryModel string       `json:"primaryModel"`
	Stats        ListenerInfo `json:"stats"`
	CurrentBlock *Block       `json:"currentBlock"`
}

type ListenerInfo struct {
	CurrentListeners int `json:"currentListeners"`
}

type Block struct {
	Name            string `json:"name"`
	StartedAt       string `json:"startedAt"`
	DurationMinutes int    `json:"durationMinutes"`
}

type StatsByStation map[string]StationStats

type CollectResult struct {
	TracksInserted  int `json:"tracks_inserted"`
	AiringsInserted int `json:"airings_inserted"`
	AiringsUpdated  int `json:"airings_updated"`
	Observations    int `json:"observations"`
	Skipped         int `json:"skipped"`
}

func main() {
	config := parseConfig()
	logger := log.New(os.Stdout, "", log.LstdFlags|log.Lmicroseconds)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := os.MkdirAll(filepath.Dir(config.DBPath), 0o755); err != nil && filepath.Dir(config.DBPath) != "." {
		logger.Fatalf("create sqlite directory: %v", err)
	}

	db, err := openDB(config.DBPath)
	if err != nil {
		logger.Fatalf("open sqlite db: %v", err)
	}
	defer db.Close()

	if err := migrate(ctx, db); err != nil {
		logger.Fatalf("migrate sqlite db: %v", err)
	}

	client := &http.Client{Timeout: 20 * time.Second}
	collector := Collector{
		Config: config,
		DB:     db,
		Client: client,
		Logger: logger,
	}

	if err := collector.Tick(ctx); err != nil {
		logger.Printf("collect failed: %v", err)
		if config.Once {
			os.Exit(1)
		}
	}

	if config.Once {
		return
	}

	ticker := time.NewTicker(config.Interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			logger.Print("shutting down")
			return
		case <-ticker.C:
			if err := collector.Tick(ctx); err != nil {
				logger.Printf("collect failed: %v", err)
			}
		}
	}
}

func parseConfig() Config {
	var config Config
	flag.StringVar(&config.MetadataURL, "metadata-url", envString("ANDON_METADATA_URL", defaultMetadataURL), "Andon public metadata endpoint")
	flag.StringVar(&config.StatsURL, "stats-url", envString("ANDON_STATS_URL", defaultStatsURL), "Andon public stats endpoint")
	flag.StringVar(&config.DBPath, "db", envString("SQLITE_PATH", defaultDBPath), "SQLite database path")
	flag.DurationVar(&config.Interval, "interval", envDuration("POLL_INTERVAL", time.Minute), "poll interval")
	flag.BoolVar(&config.Once, "once", envBool("COLLECT_ONCE", false), "run one collection pass and exit")
	flag.Parse()

	if config.Interval < 10*time.Second {
		config.Interval = 10 * time.Second
	}
	return config
}

type Collector struct {
	Config Config
	DB     *sql.DB
	Client *http.Client
	Logger *log.Logger
}

func (collector Collector) Tick(ctx context.Context) error {
	observedAt := time.Now().UTC()

	var metadata MetadataResponse
	if err := collector.fetchJSON(ctx, collector.Config.MetadataURL, &metadata); err != nil {
		return fmt.Errorf("fetch metadata: %w", err)
	}

	var stats StatsResponse
	if err := collector.fetchJSON(ctx, collector.Config.StatsURL, &stats); err != nil {
		return fmt.Errorf("fetch stats: %w", err)
	}

	result, err := collector.record(ctx, observedAt, metadata, stats.byStation())
	if err != nil {
		return err
	}

	payload, _ := json.Marshal(result)
	collector.Logger.Printf("collected %s", payload)
	return nil
}

func (collector Collector) fetchJSON(ctx context.Context, url string, destination any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("User-Agent", "AndonConeHistoryCollector/1.0")

	response, err := collector.Client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode < 200 || response.StatusCode > 299 {
		return fmt.Errorf("unexpected status %s", response.Status)
	}

	return json.NewDecoder(response.Body).Decode(destination)
}

func (stats StatsResponse) byStation() StatsByStation {
	byID := make(StatsByStation, len(stats.Stations))
	for _, station := range stats.Stations {
		id := station.ID
		if id == "" {
			id = station.StationID
		}
		if id != "" {
			station.ID = id
			byID[id] = station
		}
	}
	return byID
}

func (collector Collector) record(ctx context.Context, observedAt time.Time, metadata MetadataResponse, stats StatsByStation) (CollectResult, error) {
	tx, err := collector.DB.BeginTx(ctx, nil)
	if err != nil {
		return CollectResult{}, err
	}
	defer tx.Rollback()

	observedMinute := observedAt.Truncate(time.Minute)
	stationIDs := mergedStationIDs(metadata.Stations, stats)
	result := CollectResult{}

	for _, stationID := range stationIDs {
		track := metadata.Stations[stationID]
		stationStats, hasStats := stats[stationID]
		if err := upsertStation(ctx, tx, stationID, stationStats, hasStats); err != nil {
			return CollectResult{}, fmt.Errorf("upsert station %s: %w", stationID, err)
		}

		trackID, insertedTrack, skipped, err := upsertTrack(ctx, tx, observedMinute, track)
		if err != nil {
			return CollectResult{}, fmt.Errorf("upsert track %s: %w", stationID, err)
		}
		if insertedTrack {
			result.TracksInserted++
		}

		if err := upsertObservation(ctx, tx, stationID, trackID, observedAt, observedMinute, track, stationStats, hasStats); err != nil {
			return CollectResult{}, fmt.Errorf("insert observation %s: %w", stationID, err)
		}
		result.Observations++

		if skipped {
			result.Skipped++
			continue
		}

		changed, err := recordAiring(ctx, tx, stationID, trackID, observedMinute, track)
		if err != nil {
			return CollectResult{}, fmt.Errorf("record airing %s: %w", stationID, err)
		}
		if changed {
			result.AiringsInserted++
		} else {
			result.AiringsUpdated++
		}
	}

	if err := tx.Commit(); err != nil {
		return CollectResult{}, err
	}
	return result, nil
}

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(ON)")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	return db, nil
}

func migrate(ctx context.Context, db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS stations (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			host TEXT,
			stream_url TEXT,
			image_url TEXT,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS tracks (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			title TEXT NOT NULL,
			artist TEXT NOT NULL,
			title_norm TEXT NOT NULL,
			artist_norm TEXT NOT NULL,
			first_seen_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,
			UNIQUE(title_norm, artist_norm)
		)`,
		`CREATE TABLE IF NOT EXISTS observations (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			station_id TEXT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
			track_id INTEGER REFERENCES tracks(id) ON DELETE SET NULL,
			observed_at TEXT NOT NULL,
			observed_minute TEXT NOT NULL,
			minute_epoch INTEGER NOT NULL,
			observed_date TEXT NOT NULL,
			minute_of_day INTEGER NOT NULL,
			weekday_utc INTEGER NOT NULL,
			online INTEGER,
			listener_count INTEGER,
			current_block_name TEXT,
			current_block_started_at TEXT,
			raw_metadata TEXT,
			raw_stats TEXT,
			created_at TEXT NOT NULL,
			UNIQUE(station_id, observed_minute)
		)`,
		`CREATE TABLE IF NOT EXISTS airings (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			station_id TEXT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
			track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
			first_seen_at TEXT NOT NULL,
			last_seen_at TEXT NOT NULL,
			observation_count INTEGER NOT NULL DEFAULT 1,
			source TEXT NOT NULL DEFAULT 'metadata',
			raw_metadata TEXT,
			created_at TEXT NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_observations_station_observed
			ON observations (station_id, observed_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_observations_station_minute
			ON observations (station_id, minute_epoch DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_observations_minute_of_day
			ON observations (station_id, minute_of_day, observed_date DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_observations_track_observed
			ON observations (track_id, observed_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_airings_station_seen
			ON airings (station_id, first_seen_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_airings_track_seen
			ON airings (track_id, first_seen_at DESC)`,
		`CREATE VIEW IF NOT EXISTS station_minute_observations AS
			SELECT
				observations.station_id,
				stations.name AS station_name,
				observations.observed_minute,
				observations.minute_epoch,
				observations.observed_date,
				observations.minute_of_day,
				observations.weekday_utc,
				observations.track_id,
				tracks.title,
				tracks.artist,
				observations.listener_count,
				observations.current_block_name
			FROM observations
			JOIN stations ON stations.id = observations.station_id
			LEFT JOIN tracks ON tracks.id = observations.track_id`,
		`CREATE VIEW IF NOT EXISTS current_station_airings AS
			SELECT
				airings.station_id,
				airings.track_id,
				tracks.title,
				tracks.artist,
				airings.first_seen_at,
				airings.last_seen_at,
				airings.observation_count
			FROM airings
			JOIN tracks ON tracks.id = airings.track_id
			WHERE airings.id = (
				SELECT id
				FROM airings latest
				WHERE latest.station_id = airings.station_id
				ORDER BY latest.first_seen_at DESC
				LIMIT 1
			)`,
		`CREATE VIEW IF NOT EXISTS track_airing_counts AS
			SELECT
				airings.station_id,
				stations.name AS station_name,
				airings.track_id,
				tracks.title,
				tracks.artist,
				count(*) AS airing_count,
				min(airings.first_seen_at) AS first_played_at,
				max(airings.first_seen_at) AS last_played_at
			FROM airings
			JOIN tracks ON tracks.id = airings.track_id
			JOIN stations ON stations.id = airings.station_id
			GROUP BY airings.station_id, airings.track_id`,
		`CREATE VIEW IF NOT EXISTS hourly_track_observations AS
			SELECT
				observations.station_id,
				stations.name AS station_name,
				observations.track_id,
				tracks.title,
				tracks.artist,
				strftime('%Y-%m-%dT%H:00:00Z', observations.observed_at) AS observed_hour,
				count(*) AS observation_count
			FROM observations
			JOIN tracks ON tracks.id = observations.track_id
			JOIN stations ON stations.id = observations.station_id
			GROUP BY observations.station_id, observations.track_id, observed_hour`,
		`CREATE VIEW IF NOT EXISTS same_minute_history_similarity AS
			SELECT
				current.station_id,
				stations.name AS station_name,
				current.observed_minute,
				current.observed_date,
				current.minute_of_day,
				prior.observed_minute AS prior_observed_minute,
				(current.minute_epoch - prior.minute_epoch) / 86400 AS days_back,
				current.track_id AS current_track_id,
				current_track.title AS current_title,
				current_track.artist AS current_artist,
				prior.track_id AS prior_track_id,
				prior_track.title AS prior_title,
				prior_track.artist AS prior_artist,
				CASE
					WHEN current.track_id IS NOT NULL AND current.track_id = prior.track_id THEN 1.0
					ELSE 0.0
				END AS exact_track_match
			FROM observations current
			JOIN observations prior
				ON prior.station_id = current.station_id
				AND prior.minute_of_day = current.minute_of_day
				AND prior.minute_epoch < current.minute_epoch
				AND (current.minute_epoch - prior.minute_epoch) % 86400 = 0
				AND (current.minute_epoch - prior.minute_epoch) BETWEEN 86400 AND 2592000
			JOIN stations ON stations.id = current.station_id
			LEFT JOIN tracks current_track ON current_track.id = current.track_id
			LEFT JOIN tracks prior_track ON prior_track.id = prior.track_id`,
		`CREATE VIEW IF NOT EXISTS same_minute_prior_day_similarity AS
			SELECT *
			FROM same_minute_history_similarity
			WHERE days_back = 1`,
	}

	for _, statement := range statements {
		if _, err := db.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	return nil
}

func upsertStation(ctx context.Context, tx *sql.Tx, stationID string, stats StationStats, hasStats bool) error {
	seed := knownStations[stationID]
	name := firstNonEmpty(stats.Name, seed.Name, stationID)
	host := firstNonEmpty(stats.PrimaryModel, stats.Subtitle, seed.Host)
	streamURL := firstNonEmpty(stats.StreamURL, seed.StreamURL)
	imageURL := ""
	if hasStats {
		imageURL = clean(stats.ImageURL)
	}

	_, err := tx.ExecContext(
		ctx,
		`INSERT INTO stations (id, name, host, stream_url, image_url, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			name = excluded.name,
			host = excluded.host,
			stream_url = excluded.stream_url,
			image_url = coalesce(nullif(excluded.image_url, ''), stations.image_url),
			updated_at = excluded.updated_at`,
		stationID,
		name,
		nullable(host),
		nullable(streamURL),
		nullable(imageURL),
		time.Now().UTC().Format(time.RFC3339),
	)
	return err
}

func upsertTrack(ctx context.Context, tx *sql.Tx, observedAt time.Time, track TrackMetadata) (trackID int64, inserted bool, skipped bool, err error) {
	title := clean(track.Title)
	artist := clean(track.Artist)
	if title == "" || artist == "" {
		return 0, false, true, nil
	}

	titleNorm := normalize(title)
	artistNorm := normalize(artist)
	now := observedAt.Format(time.RFC3339)

	err = tx.QueryRowContext(
		ctx,
		`SELECT id FROM tracks WHERE title_norm = ? AND artist_norm = ?`,
		titleNorm,
		artistNorm,
	).Scan(&trackID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0, false, false, err
	}

	if err == nil {
		_, err = tx.ExecContext(
			ctx,
			`UPDATE tracks SET title = ?, artist = ?, updated_at = ? WHERE id = ?`,
			title,
			artist,
			now,
			trackID,
		)
		return trackID, false, false, err
	}

	result, err := tx.ExecContext(
		ctx,
		`INSERT INTO tracks (title, artist, title_norm, artist_norm, first_seen_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)`,
		title,
		artist,
		titleNorm,
		artistNorm,
		now,
		now,
	)
	if err != nil {
		return 0, false, false, err
	}
	trackID, err = result.LastInsertId()
	return trackID, true, false, err
}

func upsertObservation(ctx context.Context, tx *sql.Tx, stationID string, trackID int64, observedAt time.Time, observedMinute time.Time, track TrackMetadata, stats StationStats, hasStats bool) error {
	var blockName, blockStartedAt sql.NullString
	var listenerCount sql.NullInt64
	var nullableTrackID sql.NullInt64
	var rawStats sql.NullString

	if trackID != 0 {
		nullableTrackID = sql.NullInt64{Int64: trackID, Valid: true}
	}
	if hasStats {
		listenerCount = sql.NullInt64{Int64: int64(stats.Stats.CurrentListeners), Valid: true}
		if stats.CurrentBlock != nil {
			blockName = nullable(stats.CurrentBlock.Name)
			blockStartedAt = nullable(stats.CurrentBlock.StartedAt)
		}
		rawStats = jsonNullString(stats)
	}

	_, err := tx.ExecContext(
		ctx,
		`INSERT INTO observations (
			station_id,
			track_id,
			observed_at,
			observed_minute,
			minute_epoch,
			observed_date,
			minute_of_day,
			weekday_utc,
			online,
			listener_count,
			current_block_name,
			current_block_started_at,
			raw_metadata,
			raw_stats,
			created_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(station_id, observed_minute) DO UPDATE SET
			track_id = excluded.track_id,
			observed_at = excluded.observed_at,
			minute_epoch = excluded.minute_epoch,
			observed_date = excluded.observed_date,
			minute_of_day = excluded.minute_of_day,
			weekday_utc = excluded.weekday_utc,
			online = excluded.online,
			listener_count = excluded.listener_count,
			current_block_name = excluded.current_block_name,
			current_block_started_at = excluded.current_block_started_at,
			raw_metadata = excluded.raw_metadata,
			raw_stats = excluded.raw_stats`,
		stationID,
		nullableTrackID,
		observedAt.Format(time.RFC3339),
		observedMinute.Format(time.RFC3339),
		observedMinute.Unix(),
		observedMinute.Format(time.DateOnly),
		minuteOfDay(observedMinute),
		int(observedMinute.Weekday()),
		boolInt(track.Online),
		listenerCount,
		blockName,
		blockStartedAt,
		jsonNullString(track),
		rawStats,
		time.Now().UTC().Format(time.RFC3339),
	)
	return err
}

func recordAiring(ctx context.Context, tx *sql.Tx, stationID string, trackID int64, observedAt time.Time, track TrackMetadata) (changed bool, err error) {
	var latestID int64
	var latestTrackID int64
	err = tx.QueryRowContext(
		ctx,
		`SELECT id, track_id
		FROM airings
		WHERE station_id = ?
		ORDER BY first_seen_at DESC
		LIMIT 1`,
		stationID,
	).Scan(&latestID, &latestTrackID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}

	if err == nil && latestTrackID == trackID {
		_, err = tx.ExecContext(
			ctx,
			`UPDATE airings
			SET last_seen_at = ?,
				observation_count = observation_count + 1,
				raw_metadata = ?
			WHERE id = ?`,
			observedAt.Format(time.RFC3339),
			jsonNullString(track),
			latestID,
		)
		return false, err
	}

	_, err = tx.ExecContext(
		ctx,
		`INSERT INTO airings (
			station_id,
			track_id,
			first_seen_at,
			last_seen_at,
			raw_metadata,
			created_at
		) VALUES (?, ?, ?, ?, ?, ?)`,
		stationID,
		trackID,
		observedAt.Format(time.RFC3339),
		observedAt.Format(time.RFC3339),
		jsonNullString(track),
		time.Now().UTC().Format(time.RFC3339),
	)
	return true, err
}

func mergedStationIDs(metadata map[string]TrackMetadata, stats StatsByStation) []string {
	seen := make(map[string]bool)
	for stationID := range knownStations {
		seen[stationID] = true
	}
	for stationID := range metadata {
		seen[stationID] = true
	}
	for stationID := range stats {
		seen[stationID] = true
	}

	stationIDs := make([]string, 0, len(seen))
	for stationID := range seen {
		stationIDs = append(stationIDs, stationID)
	}
	sort.Strings(stationIDs)
	return stationIDs
}

func envString(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func envDuration(key string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	duration, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return duration
}

func envBool(key string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	switch value {
	case "1", "true", "yes":
		return true
	case "0", "false", "no":
		return false
	default:
		return fallback
	}
}

func clean(value string) string {
	return strings.Join(strings.Fields(value), " ")
}

func normalize(value string) string {
	return strings.ToLower(clean(value))
}

func minuteOfDay(value time.Time) int {
	return value.Hour()*60 + value.Minute()
}

func nullable(value string) sql.NullString {
	cleaned := clean(value)
	return sql.NullString{String: cleaned, Valid: cleaned != ""}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if cleaned := clean(value); cleaned != "" {
			return cleaned
		}
	}
	return ""
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func jsonNullString(value any) sql.NullString {
	data, err := json.Marshal(value)
	if err != nil {
		return sql.NullString{}
	}
	return sql.NullString{String: string(data), Valid: true}
}
