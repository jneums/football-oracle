# Soccer Oracle Frontend Specification

## Overview

Build a real-time soccer match tracking dashboard that displays live match data from the Soccer Oracle canister deployed on the Internet Computer. The oracle provides event-sourced match data with ICRC-3 logging for transparency and auditability.

## Canister Information

**Canister ID:** `iq5so-oiaaa-aaaai-q34ia-cai`  
**Network:** Internet Computer Mainnet  
**Interface:** Candid (see Motoko Interface section below)

## Core Features

### 1. Live Match Dashboard

**Primary View:**
- Display upcoming and in-progress matches
- Show match status (Scheduled, InProgress, Final, Cancelled)
- Real-time score updates (fetched from oracle every 30-60 seconds)
- Time until kickoff for scheduled matches
- Match timer for in-progress matches
- League/competition badges

**Data Source:** `query_scheduled_matches` endpoint with filters

**Key Requirements:**
- Responsive grid layout (mobile-first)
- Auto-refresh every 30-60 seconds for live matches
- Visual indicators for match status (color coding, icons)
- Timezone conversion to user's local time

### 2. Match Detail View

**Match Information:**
- Home team vs Away team
- Current score (if match started)
- Match status and time
- League/competition name
- Scheduled kickoff time
- Oracle ID for reference

**Event Timeline:**
- Chronological list of all events for the match
- Event types: Match Scheduled, Match In Progress, Match Final, Match Cancelled
- Timestamp for each event
- Score changes highlighted
- API source information (transparency)

**Data Sources:** 
- `get_match_events` for event history
- `get_latest_event` for current state

### 3. League Filter/Navigator

**Functionality:**
- Filter matches by league/competition
- Show match count per league
- Quick navigation between leagues
- "All Leagues" view

**Monitored Leagues:**
- UEFA Champions League
- UEFA Champions League Women
- UEFA Europa League
- Premier League (England)
- La Liga (Spain)
- Bundesliga (Germany)
- Serie A (Italy)
- Ligue 1 (France)
- World Cup Qualifiers (CONCACAF)
- World Cup Qualifiers (Europe)
- Liga Nacional (Honduras)
- Primera División (Costa Rica)

**Data Source:** `get_monitored_leagues` + league name mapping

### 4. Time-Based Navigation

**Views:**
- Today's matches
- Tomorrow's matches
- This week's matches
- Date range picker

**Implementation:**
- Use `startTime` and `endTime` parameters in `query_scheduled_matches`
- Convert user's date selection to nanosecond timestamps

### 5. Match Status Filtering

**Filter Options:**
- All matches
- Scheduled (upcoming)
- Live (in progress)
- Finished (final)
- Cancelled

**Implementation:**
- Use `status` parameter in `query_scheduled_matches`
- Visual badges for each status type

### 6. Pagination

**Requirements:**
- Show 20-50 matches per page
- Load more / infinite scroll option
- Page navigation controls
- Total match count indicator

**Implementation:**
- Use `limit` and `offset` parameters in `query_scheduled_matches`
- Client-side state management for current page

## Design Requirements

### Visual Hierarchy

1. **Status Priority:**
   - Live matches (highest priority - prominent display)
   - Upcoming matches (next 3 hours)
   - Scheduled matches (later)
   - Finished matches (collapsed/archived)

2. **Color Scheme:**
   - Live: Green/Vibrant (pulsing indicator)
   - Scheduled: Blue/Neutral
   - Final: Gray/Muted
   - Cancelled: Red/Warning

3. **Typography:**
   - Match scores: Large, bold
   - Team names: Medium weight
   - Time/status: Small, secondary color
   - League: Label/badge style

### Responsive Design

**Mobile (320px - 768px):**
- Single column card layout
- Collapsible filters
- Swipe navigation between leagues
- Bottom navigation bar

**Tablet (768px - 1024px):**
- Two column grid
- Side panel for filters
- Expandable match details

**Desktop (1024px+):**
- Three column grid for match cards
- Persistent sidebar navigation
- Split view: list + detail panel
- Dashboard-style layout

## Technical Requirements

### Frontend Stack Recommendations

**Framework:** React, Vue, or Svelte  
**IC Integration:** 
- `@dfinity/agent` for canister communication
- `@dfinity/candid` for interface definitions
- `@dfinity/auth-client` (if authentication needed)

**State Management:** 
- Redux, Zustand, or Context API
- Cache oracle data for 30-60 seconds
- Invalidate cache on user action (refresh)

**UI Library (Optional):**
- Material-UI, Chakra UI, or Tailwind CSS
- Icons: Font Awesome or Heroicons

### Data Fetching Strategy

**Polling for Live Updates:**
```javascript
// Fetch live matches every 30 seconds
setInterval(async () => {
  const now = Date.now() * 1_000_000; // Convert to nanoseconds
  const matches = await canister.query_scheduled_matches({
    startTime: [BigInt(now)],
    endTime: [],
    status: ["InProgress"],
    league: [],
    limit: [],
    offset: []
  });
  updateMatches(matches);
}, 30000);
```

**Initial Load:**
```javascript
// Load upcoming matches (next 24 hours)
const now = Date.now() * 1_000_000;
const tomorrow = (Date.now() + 86400000) * 1_000_000;

const upcomingMatches = await canister.query_scheduled_matches({
  startTime: [BigInt(now)],
  endTime: [BigInt(tomorrow)],
  status: ["Scheduled"],
  league: [],
  limit: [50],
  offset: [0]
});
```

**Pagination:**
```javascript
// Load page 2 (offset 20, limit 20)
const page2 = await canister.query_scheduled_matches({
  startTime: [],
  endTime: [],
  status: [],
  league: [],
  limit: [20],
  offset: [20]
});
```

### Error Handling

**Required:**
- Network error handling (canister unreachable)
- Empty state displays (no matches found)
- Loading states (skeleton screens)
- Retry logic for failed requests
- Toast notifications for errors

### Performance Optimization

**Caching:**
- Cache match data for 30-60 seconds
- Use service workers for offline support
- LocalStorage for user preferences (favorite leagues, timezone)

**Lazy Loading:**
- Load match details on demand
- Paginate event history for matches with many events
- Progressive image loading for team logos (if added)

**Optimization:**
- Debounce filter changes
- Virtual scrolling for large match lists
- Memoize expensive computations

## API Integration Details

### Canister Connection Setup

```typescript
import { Actor, HttpAgent } from '@dfinity/agent';
import { idlFactory } from './declarations/main'; // Generated from Candid

const agent = new HttpAgent({
  host: 'https://ic0.app', // Mainnet
});

const canisterId = 'iq5so-oiaaa-aaaai-q34ia-cai';

const canister = Actor.createActor(idlFactory, {
  agent,
  canisterId,
});
```

### Time Conversion Utilities

```typescript
// Convert JavaScript Date to nanoseconds
function dateToNanos(date: Date): bigint {
  return BigInt(date.getTime()) * 1_000_000n;
}

// Convert nanoseconds to JavaScript Date
function nanosToDate(nanos: bigint): Date {
  return new Date(Number(nanos / 1_000_000n));
}

// Format match time
function formatMatchTime(nanos: bigint): string {
  const date = nanosToDate(nanos);
  const now = new Date();
  const diff = date.getTime() - now.getTime();
  
  if (diff < 0) return 'Started';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h`;
  return date.toLocaleDateString();
}
```

### Type Definitions

```typescript
interface ScheduledMatchInfo {
  oracleId: bigint;
  apiFootballId: string;
  homeTeam: string;
  awayTeam: string;
  league: string;
  scheduledTime: bigint; // nanoseconds
  status: string; // "Scheduled" | "InProgress" | "Final" | "Cancelled"
}

interface OracleEvent {
  oracleId: bigint;
  timestamp: bigint;
  eventType: EventType;
  eventData: EventData;
  sourceConsensus: ApiSource[];
}

type EventType = 
  | { MatchScheduled: null }
  | { MatchInProgress: null }
  | { MatchFinal: null }
  | { MatchCancelled: null };

type EventData = 
  | { MatchScheduled: { homeTeam: string; awayTeam: string; scheduledTime: bigint } }
  | { MatchInProgress: { homeTeam: string; awayTeam: string; homeScore: bigint; awayScore: bigint; minute: [] | [bigint] } }
  | { MatchFinal: { homeTeam: string; awayTeam: string; homeScore: bigint; awayScore: bigint; outcome: MatchOutcome } }
  | { MatchCancelled: { homeTeam: string; awayTeam: string; reason: string } };

type MatchOutcome = 
  | { HomeWin: null }
  | { AwayWin: null }
  | { Draw: null };

interface ApiSource {
  provider: string;
  url: string;
  timestamp: bigint;
}
```

## User Stories

### Story 1: View Live Matches
**As a** soccer fan  
**I want to** see all currently live matches  
**So that** I can track scores in real-time

**Acceptance Criteria:**
- Live matches displayed prominently at top
- Scores update automatically every 30-60 seconds
- Visual indicator shows match is live (pulsing dot, "LIVE" badge)
- Match time shown (e.g., "42'" for 42nd minute)

### Story 2: Check Upcoming Matches
**As a** betting platform operator  
**I want to** see matches scheduled in the next 24 hours  
**So that** I can prepare betting markets

**Acceptance Criteria:**
- Time-based filter shows next 24 hours
- Countdown to kickoff displayed
- Can filter by specific league
- Paginated if more than 50 matches

### Story 3: View Match History
**As a** data analyst  
**I want to** see all events for a completed match  
**So that** I can verify the match timeline

**Acceptance Criteria:**
- Click match to see detail view
- Event timeline shows all updates chronologically
- Each event shows timestamp and data
- Can see API source for transparency

### Story 4: Filter by League
**As a** Premier League enthusiast  
**I want to** filter matches by Premier League only  
**So that** I only see matches I care about

**Acceptance Criteria:**
- League filter dropdown/sidebar
- Match count shown per league
- Filter persists across page navigation
- Can clear filter to see all leagues

### Story 5: Mobile Experience
**As a** mobile user  
**I want to** track matches on my phone  
**So that** I can stay updated on the go

**Acceptance Criteria:**
- Responsive design works on mobile
- Touch-friendly interface
- Fast loading times
- Minimal data usage (optimized API calls)

## Deliverables

### Phase 1: MVP (Week 1-2)
- [ ] Basic match list display
- [ ] Live score updates (polling)
- [ ] Match status indicators
- [ ] League filtering
- [ ] Responsive layout
- [ ] Connection to canister

### Phase 2: Enhanced Features (Week 3-4)
- [ ] Match detail view with event timeline
- [ ] Time-based filtering (today, tomorrow, date range)
- [ ] Pagination with load more
- [ ] Status filtering (live, scheduled, final)
- [ ] Loading states and error handling
- [ ] Performance optimization

### Phase 3: Polish (Week 5)
- [ ] UI/UX refinements
- [ ] Animations and transitions
- [ ] Accessibility (WCAG 2.1 AA)
- [ ] Cross-browser testing
- [ ] Mobile optimization
- [ ] Documentation

## Testing Requirements

**Unit Tests:**
- Time conversion utilities
- Data transformation functions
- Component rendering

**Integration Tests:**
- Canister connection
- API data fetching
- State management

**E2E Tests:**
- User flows for main stories
- Filter combinations
- Pagination navigation

**Performance Tests:**
- Lighthouse score > 90
- First Contentful Paint < 1.5s
- Time to Interactive < 3.5s

## Accessibility

**Requirements:**
- Semantic HTML5
- ARIA labels for dynamic content
- Keyboard navigation support
- Screen reader compatible
- Color contrast ratios WCAG AA compliant
- Focus indicators visible

## Browser Support

**Target:**
- Chrome/Edge (last 2 versions)
- Firefox (last 2 versions)
- Safari (last 2 versions)
- Mobile Safari (iOS 14+)
- Chrome Mobile (Android 10+)

## Deployment

**Hosting Options:**
1. **Internet Computer (Recommended):** Deploy as asset canister alongside oracle
2. **Traditional Hosting:** Vercel, Netlify, or similar (connects to IC canister)
3. **IPFS:** Decentralized hosting with IC backend

**Environment:**
- Production: Mainnet canister (iq5so-oiaaa-aaaai-q34ia-cai)
- No staging environment needed (query calls are read-only)

## Future Enhancements (Post-MVP)

- [ ] User accounts and favorite teams
- [ ] Push notifications for match events
- [ ] Statistical analysis and trends
- [ ] Historical data charts
- [ ] WebSocket alternative for real-time updates
- [ ] Team logos and competition branding
- [ ] Social sharing features
- [ ] Betting odds integration (if applicable)
- [ ] Dark mode theme
- [ ] Multiple language support

## Questions for Frontend Team

1. **Framework Preference:** React, Vue, or Svelte?
2. **UI Library:** Which component library do you prefer?
3. **State Management:** Redux, Zustand, or Context API?
4. **Deployment Target:** IC asset canister or traditional hosting?
5. **Design Assets:** Do you need Figma mockups or wireframes?
6. **Timeline:** Can you deliver MVP in 2 weeks?

## Support & Resources

**Documentation:**
- Query API Documentation: `/QUERY_API.md` (in repository)
- Internet Computer Docs: https://internetcomputer.org/docs
- Dfinity Agent Docs: https://agent-js.icp.xyz/

**Canister Interface:**
- Candid UI: https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.ic0.app/?id=iq5so-oiaaa-aaaai-q34ia-cai
- See Motoko Interface section below for complete API

**Contact:**
- Technical questions: [Your contact]
- Design questions: [Design lead contact]
- Repository: https://github.com/jneums/football-oracle

---

## Motoko Interface (Candid IDL)

```motoko
// Type Definitions
type MatchOutcome = variant {
  HomeWin;
  AwayWin;
  Draw;
};

type EventType = variant {
  MatchScheduled;
  MatchInProgress;
  MatchFinal;
  MatchCancelled;
};

type EventData = variant {
  MatchScheduled : record {
    homeTeam : text;
    awayTeam : text;
    scheduledTime : nat;
  };
  MatchInProgress : record {
    homeTeam : text;
    awayTeam : text;
    homeScore : nat;
    awayScore : nat;
    minute : opt nat;
  };
  MatchFinal : record {
    homeTeam : text;
    awayTeam : text;
    homeScore : nat;
    awayScore : nat;
    outcome : MatchOutcome;
  };
  MatchCancelled : record {
    homeTeam : text;
    awayTeam : text;
    reason : text;
  };
};

type ApiSource = record {
  provider : text;
  url : text;
  timestamp : nat;
};

type OracleEvent = record {
  oracleId : nat;
  timestamp : nat;
  eventType : EventType;
  eventData : EventData;
  sourceConsensus : vec ApiSource;
};

type ScheduledMatchInfo = record {
  oracleId : nat;
  apiFootballId : text;
  homeTeam : text;
  awayTeam : text;
  league : text;
  scheduledTime : nat;
  status : text;
};

type GetScheduledMatchesRequest = record {
  startTime : opt nat;
  endTime : opt nat;
  status : opt text;
  league : opt text;
  limit : opt nat;
  offset : opt nat;
};

type EventsResult = variant {
  Ok : vec OracleEvent;
  Error : variant {
    MatchNotFound;
  };
};

// Service Interface
service : {
  // Primary Query Methods (READ-ONLY - No authentication required)
  
  // Get scheduled matches with filtering and pagination
  query_scheduled_matches : (GetScheduledMatchesRequest) -> (vec ScheduledMatchInfo) query;
  
  // Get all events for a specific match
  get_match_events : (nat) -> (EventsResult) query;
  
  // Get the latest event for a match
  get_latest_event : (nat) -> (opt OracleEvent) query;
  
  // Get list of monitored league IDs
  get_monitored_leagues : () -> (vec nat) query;
  
  // Deprecated: Use query_scheduled_matches instead
  get_scheduled_matches : () -> (vec ScheduledMatchInfo) query;
}
```

### Key Query Methods for Frontend

#### 1. `query_scheduled_matches`

**Primary method for displaying matches.**

```typescript
// TypeScript example
const matches = await canister.query_scheduled_matches({
  startTime: [BigInt(Date.now() * 1_000_000)], // Now
  endTime: [BigInt((Date.now() + 86400000) * 1_000_000)], // +24h
  status: ["Scheduled"], // or ["InProgress"], ["Final"], etc.
  league: [], // Empty = all leagues, or ["Premier League"]
  limit: [20], // 20 matches per page
  offset: [0] // Start at beginning
});
```

**Use Cases:**
- Homepage: Upcoming matches (next 24 hours)
- Live view: Matches with status "InProgress"
- League page: Filter by specific league
- History: Finished matches with status "Final"

#### 2. `get_match_events`

**Get complete event history for a match.**

```typescript
// TypeScript example
const result = await canister.get_match_events(111n); // Oracle ID

if ('Ok' in result) {
  const events = result.Ok;
  events.forEach(event => {
    console.log('Time:', nanosToDate(event.timestamp));
    console.log('Type:', Object.keys(event.eventType)[0]);
    console.log('Data:', event.eventData);
  });
}
```

**Use Cases:**
- Match detail view: Show complete timeline
- Verification: Display API sources for transparency
- Analytics: Track score changes over time

#### 3. `get_latest_event`

**Get current state of a match (most recent event).**

```typescript
// TypeScript example
const latestEvent = await canister.get_latest_event(111n);

if (latestEvent.length > 0) {
  const event = latestEvent[0];
  if ('MatchInProgress' in event.eventData) {
    const data = event.eventData.MatchInProgress;
    console.log(`${data.homeScore} - ${data.awayScore}`);
  }
}
```

**Use Cases:**
- Live score display: Get current score without all history
- Status check: Quick check if match finished
- Performance: Faster than fetching all events

#### 4. `get_monitored_leagues`

**Get list of league IDs being monitored.**

```typescript
// TypeScript example
const leagueIds = await canister.get_monitored_leagues();
// Returns: [2n, 3n, 31n, 32n, 39n, 61n, 78n, 135n, 140n, 162n, 234n, 525n]

// Map to friendly names
const leagueNames = {
  2: "UEFA Champions League",
  3: "UEFA Europa League",
  31: "World Cup - Qualification CONCACAF",
  32: "World Cup - Qualification Europe",
  39: "Premier League",
  61: "Ligue 1",
  78: "Bundesliga",
  135: "Serie A",
  140: "La Liga",
  162: "Primera División (Costa Rica)",
  234: "Liga Nacional (Honduras)",
  525: "UEFA Champions League Women"
};
```

**Use Cases:**
- Navigation: Build league filter menu
- Statistics: Show match count per league
- UI: Display league badges/icons

---

## Example Frontend Component Structure

```
src/
├── components/
│   ├── MatchCard.tsx          // Individual match display
│   ├── MatchList.tsx           // Grid of match cards
│   ├── MatchDetail.tsx         // Full match view with events
│   ├── EventTimeline.tsx       // Event history display
│   ├── LeagueFilter.tsx        // League selection
│   ├── StatusFilter.tsx        // Status selection
│   ├── TimeRangeFilter.tsx     // Date/time picker
│   └── Pagination.tsx          // Page navigation
├── hooks/
│   ├── useMatches.ts           // Fetch and cache matches
│   ├── useMatchEvents.ts       // Fetch match events
│   ├── useLeagues.ts           // Fetch league list
│   └── usePolling.ts           // Auto-refresh logic
├── utils/
│   ├── canister.ts             // Canister connection setup
│   ├── time.ts                 // Time conversion utilities
│   └── formatting.ts           // Display formatting
├── types/
│   └── oracle.ts               // TypeScript type definitions
└── pages/
    ├── Home.tsx                // Main dashboard
    ├── LiveMatches.tsx         // Live matches view
    ├── League.tsx              // League-specific view
    └── Match.tsx               // Match detail page
```

## Example Implementation Snippets

### Match Card Component

```tsx
import React from 'react';
import { ScheduledMatchInfo } from '../types/oracle';
import { formatMatchTime } from '../utils/time';

interface MatchCardProps {
  match: ScheduledMatchInfo;
  onClick: (oracleId: bigint) => void;
}

export const MatchCard: React.FC<MatchCardProps> = ({ match, onClick }) => {
  const isLive = match.status === 'InProgress';
  const isFinished = match.status === 'Final';
  
  return (
    <div 
      className={`match-card ${isLive ? 'live' : ''}`}
      onClick={() => onClick(match.oracleId)}
    >
      <div className="match-header">
        <span className="league">{match.league}</span>
        {isLive && <span className="live-badge">LIVE</span>}
      </div>
      
      <div className="match-teams">
        <div className="team">{match.homeTeam}</div>
        <div className="vs">vs</div>
        <div className="team">{match.awayTeam}</div>
      </div>
      
      <div className="match-time">
        {formatMatchTime(match.scheduledTime)}
      </div>
      
      <div className={`match-status ${match.status.toLowerCase()}`}>
        {match.status}
      </div>
    </div>
  );
};
```

### Custom Hook for Polling

```typescript
import { useEffect, useState } from 'react';
import { canister } from '../utils/canister';
import { ScheduledMatchInfo } from '../types/oracle';

export function useLiveMatches(interval: number = 30000) {
  const [matches, setMatches] = useState<ScheduledMatchInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    const fetchMatches = async () => {
      try {
        const result = await canister.query_scheduled_matches({
          startTime: [],
          endTime: [],
          status: ["InProgress"],
          league: [],
          limit: [],
          offset: []
        });
        setMatches(result);
        setError(null);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    };

    fetchMatches();
    const timer = setInterval(fetchMatches, interval);
    
    return () => clearInterval(timer);
  }, [interval]);

  return { matches, loading, error };
}
```

---

This specification provides everything your frontend dev lead needs to build a production-ready soccer oracle dashboard. The interface is fully defined, use cases are clear, and example implementations are provided.
