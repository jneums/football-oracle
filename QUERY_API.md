# Query API Documentation

## `query_scheduled_matches` - Get Scheduled Matches with Filtering

This endpoint allows consumers to query scheduled matches with flexible filtering and pagination options.

### Parameters

All parameters are optional. If no parameters are provided, all matches are returned.

```motoko
type GetScheduledMatchesRequest = {
  startTime : ?Nat;  // Filter matches scheduled after this time (nanoseconds)
  endTime : ?Nat;    // Filter matches scheduled before this time (nanoseconds)
  status : ?Text;    // Filter by status: "Scheduled", "InProgress", "Final", "Cancelled"
  league : ?Text;    // Filter by exact league name
  limit : ?Nat;      // Maximum number of matches to return
  offset : ?Nat;     // Number of matches to skip (for pagination)
};
```

### Response

Returns an array of `ScheduledMatchInfo` sorted by scheduled time (ascending):

```motoko
type ScheduledMatchInfo = {
  oracleId : Nat;
  apiFootballId : Text;
  homeTeam : Text;
  awayTeam : Text;
  league : Text;
  scheduledTime : Nat;  // Nanoseconds since Unix epoch
  status : Text;        // "Scheduled", "InProgress", "Final", or "Cancelled"
};
```

### Example Usage

#### 1. Get next 10 upcoming matches (any status)

```bash
dfx canister call main query_scheduled_matches '(record { 
  startTime = null; 
  endTime = null; 
  status = null; 
  league = null; 
  limit = opt 10; 
  offset = opt 0 
})' --ic
```

#### 2. Get scheduled matches (not started yet)

```bash
dfx canister call main query_scheduled_matches '(record { 
  startTime = null; 
  endTime = null; 
  status = opt "Scheduled"; 
  league = null; 
  limit = null; 
  offset = null 
})' --ic
```

#### 3. Get matches in next 24 hours

First calculate timestamps:
```python
import datetime
now = datetime.datetime.now(tz=datetime.timezone.utc)
now_ns = int(now.timestamp() * 1_000_000_000)
tomorrow_ns = int((now + datetime.timedelta(days=1)).timestamp() * 1_000_000_000)
```

Then query:
```bash
dfx canister call main query_scheduled_matches '(record { 
  startTime = opt (1760539770444449024:nat); 
  endTime = opt (1760626170444449024:nat); 
  status = opt "Scheduled"; 
  league = null; 
  limit = null; 
  offset = null 
})' --ic
```

#### 4. Get Premier League matches only

```bash
dfx canister call main query_scheduled_matches '(record { 
  startTime = null; 
  endTime = null; 
  status = opt "Scheduled"; 
  league = opt "Premier League"; 
  limit = null; 
  offset = null 
})' --ic
```

#### 5. Pagination example (page 2, 20 per page)

```bash
dfx canister call main query_scheduled_matches '(record { 
  startTime = null; 
  endTime = null; 
  status = null; 
  league = null; 
  limit = opt 20; 
  offset = opt 20 
})' --ic
```

#### 6. Get finished matches from a specific time range

```bash
dfx canister call main query_scheduled_matches '(record { 
  startTime = opt (1760482800000000000:nat);  # Oct 14, 2025 23:00 UTC
  endTime = opt (1760569200000000000:nat);    # Oct 15, 2025 23:00 UTC
  status = opt "Final"; 
  league = null; 
  limit = null; 
  offset = null 
})' --ic
```

### Backward Compatibility

The old `get_scheduled_matches()` method is still available but deprecated. It returns all matches without filtering:

```bash
dfx canister call main get_scheduled_matches '()' --ic
```

**Note:** For production use with many matches, always use `query_scheduled_matches` with appropriate filters and pagination.

## Best Practices

1. **Always use pagination**: Set a reasonable `limit` (e.g., 20-100 matches per query)
2. **Filter by time range**: Use `startTime` and `endTime` to get only relevant matches
3. **Filter by status**: Most consumers only need "Scheduled" or "InProgress" matches
4. **Cache results**: Matches don't change frequently, cache for at least 1 minute
5. **Use league filter**: If you only care about specific leagues, filter on the backend to reduce data transfer

## Time Conversion

Convert JavaScript timestamps to nanoseconds:
```javascript
const nowNs = BigInt(Date.now()) * 1_000_000n;
const tomorrowNs = BigInt(Date.now() + 86400000) * 1_000_000n;
```

Convert Python timestamps to nanoseconds:
```python
import time
now_ns = int(time.time() * 1_000_000_000)
tomorrow_ns = int((time.time() + 86400) * 1_000_000_000)
```

## Monitored Leagues

Current monitored leagues (use exact names for filtering):
- "Premier League"
- "La Liga"
- "Bundesliga"
- "Serie A"
- "Ligue 1"
- "UEFA Champions League"
- "UEFA Europa League"
- "World Cup - Qualification CONCACAF"
- "World Cup - Qualification Europe"
- "Liga Nacional" (Honduras)
- "Primera División" (Costa Rica)
