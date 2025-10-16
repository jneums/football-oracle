# Soccer Oracle API Quick Reference

## Connection Info
- **Canister ID:** `iq5so-oiaaa-aaaai-q34ia-cai`
- **Network:** IC Mainnet
- **Candid UI:** https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.ic0.app/?id=iq5so-oiaaa-aaaai-q34ia-cai

## Setup

```bash
npm install @dfinity/agent @dfinity/candid @dfinity/principal
```

```typescript
import { Actor, HttpAgent } from '@dfinity/agent';

const agent = new HttpAgent({ host: 'https://ic0.app' });
const canister = Actor.createActor(idlFactory, {
  agent,
  canisterId: 'iq5so-oiaaa-aaaai-q34ia-cai',
});
```

## Core API Methods

### 1. Query Matches (Primary Method)

```typescript
query_scheduled_matches(request: {
  startTime?: bigint;    // nanoseconds since epoch
  endTime?: bigint;      // nanoseconds since epoch
  status?: string;       // "Scheduled" | "InProgress" | "Final" | "Cancelled"
  league?: string;       // exact league name
  limit?: bigint;        // max results
  offset?: bigint;       // skip N results
}) -> ScheduledMatchInfo[]
```

**Examples:**

```typescript
// Get live matches
const live = await canister.query_scheduled_matches({
  status: ["InProgress"],
});

// Get next 24 hours
const now = BigInt(Date.now() * 1_000_000);
const tomorrow = now + BigInt(86400000 * 1_000_000);
const upcoming = await canister.query_scheduled_matches({
  startTime: [now],
  endTime: [tomorrow],
  status: ["Scheduled"],
  limit: [20],
});

// Get Premier League only
const epl = await canister.query_scheduled_matches({
  league: ["Premier League"],
  status: ["Scheduled"],
});
```

### 2. Get Match Events

```typescript
get_match_events(oracleId: bigint) -> Result<OracleEvent[], Error>
```

**Example:**

```typescript
const result = await canister.get_match_events(111n);
if ('Ok' in result) {
  result.Ok.forEach(event => {
    console.log(event.eventType, event.eventData);
  });
}
```

### 3. Get Latest Event

```typescript
get_latest_event(oracleId: bigint) -> OracleEvent | null
```

**Example:**

```typescript
const latest = await canister.get_latest_event(111n);
if (latest.length > 0) {
  const event = latest[0];
  if ('MatchInProgress' in event.eventData) {
    const { homeScore, awayScore } = event.eventData.MatchInProgress;
    console.log(`${homeScore} - ${awayScore}`);
  }
}
```

### 4. Get Monitored Leagues

```typescript
get_monitored_leagues() -> bigint[]
```

**Example:**

```typescript
const leagueIds = await canister.get_monitored_leagues();
// Returns: [2n, 3n, 31n, 32n, 39n, 61n, 78n, 135n, 140n, 162n, 234n, 525n]
```

## Type Definitions

```typescript
interface ScheduledMatchInfo {
  oracleId: bigint;
  apiFootballId: string;
  homeTeam: string;
  awayTeam: string;
  league: string;
  scheduledTime: bigint;  // nanoseconds
  status: "Scheduled" | "InProgress" | "Final" | "Cancelled";
}

interface OracleEvent {
  oracleId: bigint;
  timestamp: bigint;
  eventType: EventType;
  eventData: EventData;
  sourceConsensus: ApiSource[];
}

type EventData = 
  | { MatchScheduled: { homeTeam: string; awayTeam: string; scheduledTime: bigint } }
  | { MatchInProgress: { homeTeam: string; awayTeam: string; homeScore: bigint; awayScore: bigint; minute?: bigint } }
  | { MatchFinal: { homeTeam: string; awayTeam: string; homeScore: bigint; awayScore: bigint; outcome: MatchOutcome } }
  | { MatchCancelled: { homeTeam: string; awayTeam: string; reason: string } };

type MatchOutcome = { HomeWin: null } | { AwayWin: null } | { Draw: null };
```

## Time Utilities

```typescript
// JS Date -> nanoseconds
function dateToNanos(date: Date): bigint {
  return BigInt(date.getTime()) * 1_000_000n;
}

// nanoseconds -> JS Date
function nanosToDate(nanos: bigint): Date {
  return new Date(Number(nanos / 1_000_000n));
}

// Format for display
function formatMatchTime(nanos: bigint): string {
  const date = nanosToDate(nanos);
  const now = new Date();
  const diff = date.getTime() - now.getTime();
  
  if (diff < 0) return 'Started';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h`;
  return date.toLocaleString();
}
```

## League ID Mapping

```typescript
const LEAGUES = {
  2: "UEFA Champions League",
  3: "UEFA Europa League",
  31: "World Cup - Qualification CONCACAF",
  32: "World Cup - Qualification Europe",
  39: "Premier League",
  61: "Ligue 1",
  78: "Bundesliga",
  135: "Serie A",
  140: "La Liga",
  162: "Primera División",  // Costa Rica
  234: "Liga Nacional",      // Honduras
  525: "UEFA Champions League Women"
};
```

## Common Patterns

### Auto-refresh Live Matches

```typescript
useEffect(() => {
  const fetchLive = async () => {
    const matches = await canister.query_scheduled_matches({
      status: ["InProgress"]
    });
    setMatches(matches);
  };
  
  fetchLive();
  const interval = setInterval(fetchLive, 30000); // 30 seconds
  
  return () => clearInterval(interval);
}, []);
```

### Pagination

```typescript
const [page, setPage] = useState(0);
const pageSize = 20;

const matches = await canister.query_scheduled_matches({
  limit: [BigInt(pageSize)],
  offset: [BigInt(page * pageSize)]
});
```

### Filter by Date Range

```typescript
const today = new Date();
today.setHours(0, 0, 0, 0);
const tomorrow = new Date(today);
tomorrow.setDate(tomorrow.getDate() + 1);

const todayMatches = await canister.query_scheduled_matches({
  startTime: [dateToNanos(today)],
  endTime: [dateToNanos(tomorrow)]
});
```

## Error Handling

```typescript
try {
  const matches = await canister.query_scheduled_matches({});
} catch (error) {
  if (error.message.includes('unreachable')) {
    // Network error
    console.error('Canister unreachable');
  } else {
    // Other error
    console.error('Query failed:', error);
  }
}
```

## Best Practices

1. **Cache Results:** Cache for 30-60 seconds to reduce API calls
2. **Batch Queries:** Use filters to get exactly what you need
3. **Pagination:** Always use `limit` for large result sets
4. **Time Zones:** Convert nanoseconds to user's local timezone
5. **Polling:** Refresh live matches every 30-60 seconds max
6. **Error Handling:** Handle network failures gracefully

## Testing Queries

Use the Candid UI to test queries interactively:
https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.ic0.app/?id=iq5so-oiaaa-aaaai-q34ia-cai

Example query in Candid UI:
```
query_scheduled_matches(
  record {
    startTime = null;
    endTime = null;
    status = opt "InProgress";
    league = null;
    limit = opt 10;
    offset = opt 0;
  }
)
```
