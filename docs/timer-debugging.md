# Timer Debugging Guide

## Overview

The oracle uses timers to automatically fetch match data starting 1 hour before kickoff and continuing until the match status becomes `Final` or `Cancelled`. This ensures matches are never stuck in "InProgress" status, regardless of how long they take to complete.

## Timer Behavior

- **Start**: 1 hour before scheduled kickoff
- **Fetch Interval**: Every 15 minutes
- **Stop Condition**: Match status becomes `Final` or `Cancelled` (no time limit)
- **Fallback**: Hourly check ensures missed timers get started

## Symptoms

- Match finished hours ago (confirmed on API-Football) but oracle still shows `InProgress`
- Match has final score on external source but oracle shows partial score
- `lastEventTimestamp` is significantly older than expected match end time

## Root Causes (Historical - Pre Timer Fix)

Prior to the timer improvement (Nov 14, 2025), matches could get stuck because timers stopped after 3 hours regardless of match status. Potential issues included:

1. **Timer window expiration** - Match took longer than 3 hours after kickoff
2. **API rate limiting** - API-Football rejected requests during match end
3. **Network timeouts** - HTTP outcalls failed at critical moments
4. **Canister upgrades** - Upgrade occurred during active match monitoring
5. **Cycles depletion** - Insufficient cycles to complete HTTP outcalls

**Current Status**: Timers now run until match completion, eliminating the window expiration issue.

## Diagnostic Process

### Step 1: Identify Stuck Matches

Query for matches that should be final:

```bash
dfx canister call main --ic query_scheduled_matches '(record {
  status = opt variant { InProgress };
  startTime = null;
  endTime = null;
  limit = opt 100;
  offset = opt 0;
})'
```

Look for matches where:
- `scheduledTime` is >3 hours in the past
- Match is still showing `InProgress`

### Step 2: Check Timer Diagnostics

Use the timer diagnostics endpoint to see current timer state:

```bash
dfx canister call main --ic get_timer_diagnostics '(record {})'
```

This returns the 5 most recent matches with diagnostic info including:
- `hasTimer` - Whether timer is currently running
- `shouldHaveTimer` - Whether timer should be running based on time window
- `timerId` - The actual timer ID (if active)
- `hoursUntilKickoff` / `hoursAfterKickoff` - Time positioning
- `lastEventTimestamp` - When data was last fetched

**Red flags:**
- `hasTimer = true` but `shouldHaveTimer = false` (match is Final/Cancelled but timer still running - will self-clean on next cycle)
- `status = "InProgress"` but match finished hours ago externally
- `lastEventTimestamp` hasn't updated in >30 minutes during live match

### Step 3: Verify External Source

Check API-Football directly to confirm actual match status:

1. Get the API fixture ID from match details
2. Query: `https://v3.football.api-sports.io/fixtures?id={API_ID}`
3. Compare:
   - `fixture.status.short` should be "FT" (Full Time)
   - `goals.home` / `goals.away` for final score
   - `fixture.status.elapsed` for match duration

### Step 4: Check Timer State for Specific Match

To examine a specific match in detail:

```bash
# Get full match details
dfx canister call main --ic query_scheduled_matches '(record {
  status = null;
  startTime = null;
  endTime = null;
  limit = opt 1;
  offset = opt {ORACLE_ID - 1};  # Offset to get specific ID
})'

# Check timer diagnostics around that ID
dfx canister call main --ic get_timer_diagnostics '(record {
  offset = opt {ORACLE_ID - 3};
  limit = opt 10;
})'
```

## Manual Resolution

### Fix Stuck Match

Once you've identified a stuck match, manually trigger a fetch:

```bash
dfx canister call main --ic fetch_match_data '(record {
  oracleId = {ORACLE_ID};
})'
```

**Example:**
```bash
# Oracle ID 87 stuck at InProgress 0-0
dfx canister call main --ic fetch_match_data '(record { oracleId = 87 })'

# Response: (variant { Ok = 739 : nat })
# Event ID 739 created with final score
```

### Verify Fix

```bash
dfx canister call main --ic get_latest_event '({ORACLE_ID} : nat)'
```

Check that:
- `status` is now `Final`
- Scores match external source
- `outcome` is correctly set (HomeWin/AwayWin/Draw)

### Clean Up Stale Timers

If diagnostics show `hasTimer = true` but `shouldHaveTimer = false` for old matches, the timer will clean itself up on next execution. However, to force cleanup:

1. Wait for timer to execute (15-minute interval)
2. Timer logic will see `status = Final` and self-cancel
3. Verify with `get_timer_diagnostics` that `timerId = null`

**Note:** There is currently no admin function to manually cancel specific timers. If a stale timer is causing issues, it will self-clean on next cycle.

## Pagination

Timer diagnostics support pagination to handle growing match lists:

```bash
# First 5 matches (newest)
dfx canister call main --ic get_timer_diagnostics '(record {})'

# Next 5 matches
dfx canister call main --ic get_timer_diagnostics '(record {
  offset = opt 5;
  limit = opt 5;
})'

# Custom page size (max 100)
dfx canister call main --ic get_timer_diagnostics '(record {
  offset = opt 0;
  limit = opt 20;
})'
```

Results are always **newest first** (highest Oracle ID to lowest).

## Monitoring Best Practices

### Proactive Monitoring

1. **Check for stuck InProgress matches** regardless of time since kickoff:
   ```bash
   dfx canister call main --ic query_scheduled_matches "(record {
     status = opt variant { InProgress };
     startTime = null;
     endTime = null;
     limit = opt 50;
     offset = opt 0;
   })"
   ```
   Then manually verify each against API-Football.

2. **Check timer diagnostics** for anomalies:
   ```bash
   # Look for hasTimer != shouldHaveTimer
   dfx canister call main --ic get_timer_diagnostics '(record { limit = opt 50 })'
   ```

3. **Monitor cycles balance** to ensure HTTP outcalls can complete:
   ```bash
   dfx canister status main --ic
   ```

### Post-Incident

After manually fixing stuck matches:

1. **Document** the Oracle IDs, timestamps, and API responses
2. **Check logs** for any error patterns (if logging is enabled)
3. **Verify** no other matches from same time window are affected
4. **Monitor** next match day to see if issue reproduces

## Known Limitations

- No automatic retry logic if fetch fails during critical window
- No alerting when timer fails to execute
- No visibility into why specific timer execution failed
- Cannot manually cancel individual timers
- No health monitoring for active timers

## Future Improvements

Potential enhancements to further improve reliability:

1. **Retry logic** - Attempt fetch multiple times on failure with exponential backoff
2. **Manual timer control** - Admin functions to start/stop specific timers
3. **Timer health checks** - Periodic validation that timers are executing
4. **Event logging** - Record timer lifecycle events for debugging
5. **Adaptive intervals** - Increase fetch frequency during InProgress status
6. **Add finishTime field** - Track actual match end time vs scheduled time
7. **Timer resurrection** - Automatic restart if timer stops but match not Final

## November 14, 2025 Timer Fix

**Change**: Timers now run until match completion instead of stopping after 3 hours.

**Before**:
- Timer started 2 hours before kickoff
- Stopped 3 hours after kickoff (regardless of match status)
- Matches taking >3 hours could get stuck as InProgress

**After**:
- Timer starts 1 hour before kickoff  
- Runs every 15 minutes indefinitely
- Only stops when match becomes Final or Cancelled
- Eliminates time-based expiration issue

## Historical Issues

### November 13-14, 2025
- **Oracle ID 85** (Bermuda vs Curaçao): Stuck at InProgress 0-2, actual Final 0-7
- **Oracle ID 87** (Haiti vs Costa Rica): Stuck at InProgress 0-0, actual Final 1-0
- **Root Cause**: Timer stopped executing before match finished (within 3-hour window)
- **Resolution**: Manual `fetch_match_data` calls
- **Timer State**: Both properly cleaned up (`hasTimer = false`)

### Legacy Issues
- **Oracle ID 33** (Torino vs Napoli): Stale timer still running 647+ hours after completion
- **Oracle ID 42** (Nice vs Lyon): Stale timer still running 648+ hours after completion
- **Note**: These timers will self-clean but indicate older timer management issues
