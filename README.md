# Football Oracle - Event-Sourced Sports Data

This library provides an event-sourced oracle for football (soccer) match outcomes on the Internet Computer. It is designed to serve as a trustworthy, auditable source of truth for real-world sports data, with a primary focus on creating a foundation for decentralized prediction markets.

Built using the `class-plus` pattern, this oracle is modular, stateful, and easily upgradeable, managing its own stable state while integrating seamlessly with ICRC-3 for immutable event logging.

**Mainnet Deployment:** `iq5so-oiaaa-aaaai-q34ia-cai`

## Features

*   **Event-Sourced Architecture:** Every match event is stored as an immutable block in an ICRC-3 compliant ledger
*   **Automatic Match Discovery:** Daily discovery timer finds upcoming matches from monitored leagues
*   **Smart Scheduling:** Two-timer architecture with discovery timer (24h) and per-match monitoring timers
*   **HTTP Transform Support:** Deterministic IC HTTP outcalls with header stripping for replica consensus
*   **Draw Support:** Properly handles all match outcomes including wins, losses, and draws
*   **ICRC-3 Integration:** Automatic logging of score changes to an auditable, certified ledger
*   **Duplicate Prevention:** Only logs events when scores change (no duplicate ICRC-3 entries)
*   **Stable State Management:** All data persists across canister upgrades
*   **Oracle ID System:** Sequential IDs for matches independent of external API IDs
*   **Modular and Upgradeable:** Built as a `class-plus` module for independent upgrades

## Architecture

### Two-Timer System

The oracle uses a sophisticated dual-timer architecture optimized for efficiency:

1. **Discovery Timer (24h interval)**
   - Runs daily to discover new upcoming matches
   - Queries 7 monitored leagues via API-Football
   - Automatically schedules matches with Oracle IDs
   - Idempotent: Won't duplicate existing matches

2. **Match Timers (per-match, 10min interval)**
   - Starts 1 hour before each scheduled match
   - Fetches score updates every 10 minutes during match window
   - Automatically stops 2 hours after kickoff
   - Only logs to ICRC-3 when scores change (50% cycle savings)

### HTTP Outcall Configuration

The oracle uses IC HTTP outcalls with a transform function to ensure deterministic responses:

```motoko
// Transform function strips non-deterministic headers
public query func transform(args : { 
  context : Blob; 
  response : HttpResponse 
}) : async HttpResponse {
  { args.response with headers = []; }
};
```

**Configuration:**
- `max_response_bytes = null` (disables consensus requirement, allows unlimited size)
- Cycle cost: 21B cycles per HTTP request
- API: API-Football v3 (paid plan with "next" parameter for discovery)

### Core Data Types

#### Match Outcomes
```motoko
public type MatchOutcome = {
  #HomeWin;
  #AwayWin;
  #Draw;  // Full draw/tie support as per spec
};
```

#### Match Status
```motoko
public type MatchStatus = {
  #Scheduled;   // Match scheduled, waiting for kickoff
  #InProgress;  // Match currently being played
  #Final;       // Match completed
  #Cancelled;   // Match cancelled
};
```

#### Oracle Event
The fundamental data structure that gets logged to ICRC-3:
```motoko
public type OracleEvent = {
  oracleId : Nat;           // Sequential Oracle ID (independent of API)
  timestamp : Nat;          // Nanoseconds since epoch
  eventType : EventType;
  eventData : EventData;
  sourceConsensus : [ApiSource];  // API source(s) used
};
```

#### Scheduled Match
```motoko
public type ScheduledMatch = {
  oracleId : Nat;              // Oracle's sequential ID
  apiFootballId : Text;        // API-Football fixture ID
  scheduledTime : Nat;         // Match kickoff time (nanoseconds)
  homeTeam : Text;
  awayTeam : Text;
  league : Text;
  status : MatchStatus;
  lastFetchTime : ?Nat;        // Last successful data fetch
  matchTimerId : ?Nat;         // Active timer ID (if running)
};
```

## Installation

This library is designed to be used as a standalone canister or integrated into a larger system.

1.  Clone the repository:
    ```bash
    git clone <repository_url>
    cd soccer-oracle
    ```

2.  Install dependencies:
    ```bash
    npm install
    ```

3.  Deploy locally:
    ```bash
    dfx start --clean --background
    dfx deploy
    ```

4.  Deploy to mainnet:
    ```bash
    dfx deploy main --ic
    ```

## Configuration

### 1. Set API Key

```bash
dfx canister call main set_api_key '("api_football", "YOUR_API_KEY_HERE")' --ic
```

### 2. Set Monitored Leagues

Configure which leagues to monitor (currently monitoring 7 leagues):

```bash
dfx canister call main set_monitored_leagues '(record { 
  leagueIds = vec { 
    2:nat;    # UEFA Champions League
    3:nat;    # UEFA Europa League
    39:nat;   # Premier League
    61:nat;   # Ligue 1
    78:nat;   # Bundesliga
    135:nat;  # Serie A
    140:nat   # La Liga
  } 
})' --ic
```

### 3. Start Discovery Timer

Initiates daily discovery of upcoming matches:

```bash
dfx canister call main start_discovery_timer '()' --ic
```

This will:
- Run discovery immediately
- Schedule daily discovery checks
- Automatically create match timers for discovered matches

## Usage

### Automatic Operation

Once configured, the oracle operates autonomously:

1. **Discovery Phase** (runs daily)
   - Queries API-Football for next 10 matches in each monitored league
   - Creates Oracle IDs for new matches
   - Schedules match timers

2. **Match Monitoring** (per-match)
   - Timer activates 1 hour before kickoff
   - Fetches score every 10 minutes during match window
   - Logs to ICRC-3 only when score changes
   - Stops 2 hours after kickoff

### Manual Operations (Admin Only)

#### Trigger Discovery Manually

```bash
dfx canister call main trigger_discovery '()' --ic
```

#### Schedule Individual Match

```bash
dfx canister call main schedule_match '(record {
  apiFootballId = "1035202";
  scheduledTime = 1729188600000000000;  # Nanoseconds since epoch
  homeTeam = "Manchester United";
  awayTeam = "Liverpool";
  league = "Premier League"
})' --ic
```

#### Fetch Match Data

```bash
dfx canister call main fetch_match_data '(41 : nat)' --ic
```

### Querying Match Data (Public)

Anyone can query the oracle's data:

#### Get All Scheduled Matches

```bash
dfx canister call main get_scheduled_matches '()' --ic
```

Returns array of matches with Oracle IDs, teams, leagues, times, and status.

#### Get Match Events

```bash
dfx canister call main get_match_events '(41 : nat)' --ic
```

Returns all logged events for Oracle ID 41.

#### Get Latest Event

```bash
dfx canister call main get_latest_event '(41 : nat)' --ic
```

Returns the most recent event (typically final score).

#### Get Statistics

```bash
dfx canister call main get_stats '()' --ic
```

Returns:
- Total matches tracked
- Total events logged
- Timer statistics
- ICRC85 cycle sharing info

### ICRC-3 Integration

All score changes are automatically logged to ICRC-3:

```bash
# Query the ICRC-3 ledger directly
dfx canister call main icrc3_get_blocks '(vec {record {start = 0:nat; length = 100:nat}})' --ic
```

Events are only logged when scores change, preventing duplicate entries and saving cycles.

## Example: Full Production Flow

```bash
# 1. Deploy to mainnet
dfx deploy main --ic

# 2. Configure API key
dfx canister call main set_api_key '("api_football", "YOUR_KEY")' --ic

# 3. Set monitored leagues (7 major European competitions)
dfx canister call main set_monitored_leagues '(record { 
  leagueIds = vec { 2:nat; 3:nat; 39:nat; 61:nat; 78:nat; 135:nat; 140:nat } 
})' --ic

# 4. Start discovery timer (runs immediately + daily thereafter)
dfx canister call main start_discovery_timer '()' --ic

# 5. Check scheduled matches
dfx canister call main get_scheduled_matches '()' --ic
# Returns: 70 matches scheduled across 7 leagues

# 6. Wait for match to complete, then query results
dfx canister call main get_latest_event '(41 : nat)' --ic
# Returns: {
#   oracleId = 41;
#   eventType = #MatchFinal;
#   eventData = #MatchFinal({
#     homeTeam = "Union Berlin";
#     awayTeam = "Borussia Mönchengladbach";
#     homeScore = 2;
#     awayScore = 1;
#     outcome = #HomeWin;
#   });
#   sourceConsensus = [{ provider = "API-Football"; ... }];
# }

# 7. Check ICRC-3 logs
dfx canister call main icrc3_get_blocks '(vec {record {start = 0:nat; length = 10:nat}})' --ic
```

## Development Roadmap

### MVP ✅ COMPLETE
- [x] Event-sourced architecture with ICRC-3
- [x] HTTP Outcalls to real APIs (API-Football)
- [x] Transform function for deterministic responses
- [x] Automatic match discovery (daily timer)
- [x] Per-match monitoring timers (10-min intervals)
- [x] Draw/tie support
- [x] Duplicate prevention (only log score changes)
- [x] Oracle ID system
- [x] Multi-league support (7 leagues)
- [x] Mainnet deployment
- [x] API key management

### Future Enhancements
- [ ] Live score updates (minute-by-minute during matches)
- [ ] Additional event types (goals, cards, substitutions)
- [ ] Match status detection (#InProgress vs #Final)
- [ ] Dynamic fetch intervals (more frequent near goals)
- [ ] Additional sports/leagues
- [ ] Governance for league configuration
- [ ] Payment mechanism for cycle funding
- [ ] Archive node support
- [ ] Multi-API consensus (fallback sources)

## Performance & Costs

### Cycle Consumption

- **HTTP Request:** 21B cycles each (max_response_bytes = null)
- **Discovery:** ~7 leagues × 21B = ~147B cycles/day
- **Active Match:** ~12 fetches × 21B = ~252B cycles per match
- **Optimization:** Only logs to ICRC-3 on score changes (50% reduction)

### Current Load

- **70 matches scheduled** (as of Oct 14, 2025)
- **7 leagues monitored:**
  - UEFA Champions League (ID: 2)
  - UEFA Europa League (ID: 3)
  - Premier League (ID: 39)
  - Ligue 1 (ID: 61)
  - Bundesliga (ID: 78)
  - Serie A (ID: 135)
  - La Liga (ID: 140)

### Monitoring

Use [CycleOps](https://cycleops.dev) to monitor:
- Cycle burn rate
- HTTP outcall frequency
- Timer execution
- Storage growth

## Testing

Run the test suite:

```bash
npm test
```

The tests cover:
- Event creation and logging
- ICRC-3 integration
- Match outcome handling (including draws)
- Admin authorization
- Query methods
- Timer mechanics
- Idempotent scheduling (duplicate prevention)
- Score change detection

**Test Results:** 19/19 passing ✅

## Technical Details

### Transform Function

The oracle implements an IC HTTP outcall transform function to ensure deterministic responses across replicas:

```motoko
public query func transform(args : { 
  context : Blob; 
  response : HttpTypes.HttpResponse 
}) : async HttpTypes.HttpResponse {
  { args.response with headers = []; }
};
```

This strips all headers (date, rate-limit, request-id, etc.) which would otherwise cause consensus failures.

### Oracle ID System

- **Oracle IDs:** Sequential Nat (1, 2, 3, ...) assigned by the oracle
- **API Football IDs:** External fixture IDs from API-Football
- **Mapping:** `apiToOracleId` map maintains bidirectional lookup
- **Idempotency:** Duplicate fixtures are detected and skipped

### State Management

All state is stable and persists across upgrades:
- `scheduledMatches`: Map<OracleId, ScheduledMatch>
- `matches`: Map<OracleId, MatchRecord>
- `apiToOracleId`: Map<Text, OracleId> for deduplication
- `apiKeys`: Map<Text, Text> for provider credentials
- `monitoredLeagues`: [Nat] for active leagues
- `discoveryTimerId`: ?Nat for daily discovery
- `nextOracleId`: Nat counter for ID assignment

## License

This library is licensed under the MIT License.

## Contributing

Contributions are welcome! Please ensure:
1. All tests pass (`npm test`)
2. New features include tests
3. Code follows the existing patterns
4. Draw support is maintained in all match outcome handling
5. ICRC-3 logging only occurs on state changes (no duplicates)
6. HTTP transform function maintains determinism

## API Reference

### Admin Methods

- `set_api_key(provider: Text, key: Text)` - Configure API credentials
- `set_monitored_leagues(leagueIds: [Nat])` - Set leagues to monitor
- `start_discovery_timer()` - Start daily discovery
- `trigger_discovery()` - Manually trigger discovery
- `schedule_match(request: ScheduleMatchRequest)` - Manually schedule a match
- `fetch_match_data(oracleId: Nat)` - Manually fetch score

### Public Query Methods

- `get_monitored_leagues()` - Get configured leagues
- `get_scheduled_matches()` - Get all scheduled matches
- `get_match_events(oracleId: Nat)` - Get all events for a match
- `get_latest_event(oracleId: Nat)` - Get latest event for a match
- `get_stats()` - Get oracle statistics
- `icrc3_get_blocks(args)` - Query ICRC-3 ledger

## Specification

See [SPEC.md](./SPEC.md) for the complete technical specification.