// Football Oracle Test Suite - v0.1.0
// Single API (API-Football), Oracle ID system, Automatic scheduling

import * as path from 'node:path';
import { Principal } from "@dfinity/principal";
import { IDL } from "@dfinity/candid";
import { PocketIc, createIdentity } from "@dfinity/pic";
import type { DeferredActor, CanisterFixture } from "@dfinity/pic";
import type { Identity } from '@dfinity/agent';

// Import from the main canister's declarations
import { idlFactory as oracleIdlFactory, init as oracleInit } from "../../src/declarations/main/main.did.js";
import type { _SERVICE as OracleService } from "../../src/declarations/main/main.did";

// --- Constants and Setup ---
const ORACLE_WASM_PATH = path.resolve(__dirname, "../../.dfx/local/canisters/main/main.wasm");

// API-Football URL (single API source)
const API_FOOTBALL_URL = "https://v3.football.api-sports.io";

let pic: PocketIc;
let oracleActor: DeferredActor<OracleService>;
let oracleCanisterId: Principal;

// --- Identities ---
const adminIdentity: Identity = createIdentity("admin-principal");
const userIdentity: Identity = createIdentity("user-principal");

// Helper function to create API-Football mock response
const createApiFootballResponse = (fixtureId: string, homeScore: number, awayScore: number, status: string = "FT") => {
  return {
    response: [{
      fixture: {
        id: parseInt(fixtureId),
        status: { short: status, long: status === "FT" ? "Match Finished" : "Not Started" }
      },
      goals: { home: homeScore, away: awayScore },
      teams: {
        home: { name: "Burnley" },
        away: { name: "Manchester City" }
      },
      league: {
        id: 39,
        name: "Premier League"
      }
    }]
  };
};

// Helper function to schedule a match and mock HTTP outcalls
const scheduleAndFetchMatch = async (fixtureId: string, homeScore: number, awayScore: number) => {
  // Schedule the match
  const scheduleResult = await oracleActor.schedule_match({
    apiFootballId: fixtureId,
    scheduledTime: BigInt(Date.now() * 1_000_000), // Current time in nanoseconds
    homeTeam: "Burnley",
    awayTeam: "Manchester City",
    league: "Premier League"
  });

  const scheduleResponse = await scheduleResult();
  
  if (!("Ok" in scheduleResponse)) {
    throw new Error("Failed to schedule match");
  }

  const oracleId = scheduleResponse.Ok;

  // Fetch match data
  const fetchPromise = oracleActor.fetch_match_data({ oracleId });

  // Mock HTTP outcalls
  while (true) {
    await pic.tick(3);
    const httpRequests = await pic.getPendingHttpsOutcalls();

    if (httpRequests.length === 0) break;

    for (const request of httpRequests) {
      if (request.url.includes(API_FOOTBALL_URL)) {
        const mockData = createApiFootballResponse(fixtureId, homeScore, awayScore);
        const responseBody = new TextEncoder().encode(JSON.stringify(mockData));

        await pic.mockPendingHttpsOutcall({
          requestId: request.requestId,
          subnetId: request.subnetId,
          response: {
            type: 'success',
            statusCode: 200,
            headers: [
              ['Content-Type', 'application/json'],
              ['x-apisports-key', 'test_key']
            ],
            body: responseBody,
          },
        });
      }
    }
  }

  const fetchResult = await (await fetchPromise)();
  return { oracleId, fetchResult };
};

describe("Football Oracle v0.1.0", () => {
  beforeAll(async () => {
    pic = await PocketIc.create(process.env.PIC_URL);

    // Deploy the oracle canister
    const oracleFixture = await pic.setupCanister<OracleService>({
      sender: adminIdentity.getPrincipal(),
      idlFactory: oracleIdlFactory,
      wasm: ORACLE_WASM_PATH,
      arg: IDL.encode(oracleInit({ IDL }), [{
        oracleArgs: [{
          admin: [adminIdentity.getPrincipal()],
          api_football_key: "test_api_key",
          thesportsdb_key: "",
          football_data_key: ""
        }],
        ttArgs: [],
      }]),
    });

    oracleCanisterId = oracleFixture.canisterId;
    oracleActor = pic.createDeferredActor(oracleIdlFactory, oracleCanisterId);
  });

  afterAll(async () => {
    await pic.tearDown();
  });

  describe("Oracle ID System", () => {
    it('should assign sequential Oracle IDs to scheduled matches', async () => {
      oracleActor.setIdentity(adminIdentity);

      const result1 = await (await oracleActor.schedule_match({
        apiFootballId: "1001",
        scheduledTime: BigInt(Date.now() * 1_000_000),
        homeTeam: "Team A",
        awayTeam: "Team B",
        league: "Test League"
      }))();

      expect("Ok" in result1).toBeTruthy();
      const oracleId1 = "Ok" in result1 ? result1.Ok : 0n;
      expect(oracleId1).toBeGreaterThan(0n);

      const result2 = await (await oracleActor.schedule_match({
        apiFootballId: "1002",
        scheduledTime: BigInt(Date.now() * 1_000_000),
        homeTeam: "Team C",
        awayTeam: "Team D",
        league: "Test League"
      }))();

      expect("Ok" in result2).toBeTruthy();
      const oracleId2 = "Ok" in result2 ? result2.Ok : 0n;
      expect(oracleId2).toBe(oracleId1 + 1n);
    });

    it('should prevent duplicate scheduling of the same API fixture', async () => {
      oracleActor.setIdentity(adminIdentity);

      const fixtureId = "2001";
      
      const result1 = await (await oracleActor.schedule_match({
        apiFootballId: fixtureId,
        scheduledTime: BigInt(Date.now() * 1_000_000),
        homeTeam: "Team E",
        awayTeam: "Team F",
        league: "Test League"
      }))();

      expect("Ok" in result1).toBeTruthy();
      const oracleId1 = "Ok" in result1 ? result1.Ok : 0n;

      const result2 = await (await oracleActor.schedule_match({
        apiFootballId: fixtureId,
        scheduledTime: BigInt(Date.now() * 1_000_000),
        homeTeam: "Team E",
        awayTeam: "Team F",
        league: "Test League"
      }))();

      // Should return same Oracle ID (idempotent)
      expect("Ok" in result2).toBeTruthy();
      if ("Ok" in result2) {
        expect(result2.Ok).toBe(oracleId1);
      }
    });
  });

  describe("Admin Authorization", () => {
    it('should REJECT fetch_match_data from non-admin users', async () => {
      oracleActor.setIdentity(userIdentity);

      const fetchResult = await (await oracleActor.fetch_match_data({ oracleId: 1n }))();

      expect("Error" in fetchResult).toBeTruthy();
      if ("Error" in fetchResult) {
        expect("Unauthorized" in fetchResult.Error).toBeTruthy();
      }
    });

    it('should ACCEPT fetch_match_data from admin', async () => {
      oracleActor.setIdentity(adminIdentity);

      const { fetchResult } = await scheduleAndFetchMatch("3001", 2, 1);
      expect("Ok" in fetchResult).toBeTruthy();
    });

    it('should REJECT schedule_match from non-admin users', async () => {
      oracleActor.setIdentity(userIdentity);

      const result = await (await oracleActor.schedule_match({
        apiFootballId: "4001",
        scheduledTime: BigInt(Date.now() * 1_000_000),
        homeTeam: "Team X",
        awayTeam: "Team Y",
        league: "Test League"
      }))();

      expect("Error" in result).toBeTruthy();
      if ("Error" in result) {
        expect("Unauthorized" in result.Error).toBeTruthy();
      }
    });
  });

  describe("Event Retrieval", () => {
    let testOracleId: bigint;

    beforeAll(async () => {
      oracleActor.setIdentity(adminIdentity);
      const { oracleId } = await scheduleAndFetchMatch("5001", 3, 1);
      testOracleId = oracleId;
    });

    it('should return match events for existing Oracle ID', async () => {
      const result = await (await oracleActor.get_match_events(testOracleId))();

      expect("Ok" in result).toBeTruthy();
      if ("Ok" in result) {
        expect(Array.isArray(result.Ok)).toBeTruthy();
        expect(result.Ok.length).toBeGreaterThan(0);

        const event = result.Ok[0];
        expect(event.oracleId).toBe(testOracleId);
        expect(event).toHaveProperty("timestamp");
        expect(event).toHaveProperty("eventType");
        expect(event).toHaveProperty("eventData");
        expect(event).toHaveProperty("sourceConsensus");
      }
    });

    it('should return latest event for existing Oracle ID', async () => {
      const result = await (await oracleActor.get_latest_event(testOracleId))();

      expect(result.length).toBe(1);
      if (result.length > 0) {
        const event = result[0];
        if (event) {
          expect(event.oracleId).toBe(testOracleId);
          expect(event).toHaveProperty("eventData");
        }
      }
    });

    it('should return error for non-existent Oracle ID', async () => {
      const result = await (await oracleActor.get_match_events(99999n))();

      expect("Error" in result).toBeTruthy();
      if ("Error" in result) {
        expect("MatchNotFound" in result.Error).toBeTruthy();
      }
    });
  });

  describe("Match Outcomes", () => {
    it('should properly detect HomeWin', async () => {
      oracleActor.setIdentity(adminIdentity);

      const { oracleId } = await scheduleAndFetchMatch("6001", 3, 1);
      const result = await (await oracleActor.get_latest_event(oracleId))();

      expect(result.length).toBe(1);
      if (result.length > 0) {
        const event = result[0];
        if (event && "MatchFinal" in event.eventData) {
          const finalData = event.eventData.MatchFinal;
          expect(finalData.homeScore).toBe(3n);
          expect(finalData.awayScore).toBe(1n);
          expect("HomeWin" in finalData.outcome).toBeTruthy();
        }
      }
    });

    it('should properly detect AwayWin', async () => {
      oracleActor.setIdentity(adminIdentity);

      const { oracleId } = await scheduleAndFetchMatch("6002", 0, 2);
      const result = await (await oracleActor.get_latest_event(oracleId))();

      expect(result.length).toBe(1);
      if (result.length > 0) {
        const event = result[0];
        if (event && "MatchFinal" in event.eventData) {
          const finalData = event.eventData.MatchFinal;
          expect(finalData.homeScore).toBe(0n);
          expect(finalData.awayScore).toBe(2n);
          expect("AwayWin" in finalData.outcome).toBeTruthy();
        }
      }
    });

    it('should properly detect Draw', async () => {
      oracleActor.setIdentity(adminIdentity);

      const { oracleId } = await scheduleAndFetchMatch("6003", 2, 2);
      const result = await (await oracleActor.get_latest_event(oracleId))();

      expect(result.length).toBe(1);
      if (result.length > 0) {
        const event = result[0];
        if (event && "MatchFinal" in event.eventData) {
          const finalData = event.eventData.MatchFinal;
          expect(finalData.homeScore).toBe(2n);
          expect(finalData.awayScore).toBe(2n);
          expect("Draw" in finalData.outcome).toBeTruthy();
        }
      }
    });
  });


  describe("ICRC-3 Integration", () => {
    it('should log oracle events to ICRC-3 with correct block type', async () => {
      oracleActor.setIdentity(adminIdentity);

      await scheduleAndFetchMatch("7001", 1, 0);

      const logResult = await (await oracleActor.icrc3_get_blocks([{
        start: 0n,
        length: 100n
      }]))();

      expect(logResult.blocks).toBeDefined();
      expect(logResult.blocks.length).toBeGreaterThan(0);

      const oracleBlock = logResult.blocks.find((b: any) => {
        const blockMap = 'Map' in b.block ? b.block.Map : [];
        const btypeEntry = blockMap.find(([key, _]: [string, any]) => key === 'btype');
        return btypeEntry && 'Text' in btypeEntry[1] && btypeEntry[1].Text === 'oracle_event';
      });

      expect(oracleBlock).toBeDefined();
    });

    it('should NOT create duplicate ICRC-3 blocks for unchanged scores', async () => {
      oracleActor.setIdentity(adminIdentity);

      const { oracleId } = await scheduleAndFetchMatch("8001", 1, 1);

      const logResult1 = await (await oracleActor.icrc3_get_blocks([{
        start: 0n,
        length: 1000n
      }]))();
      const initialBlockCount = logResult1.blocks.length;

      // Fetch the same match again (same score)
      const fetchPromise = oracleActor.fetch_match_data({ oracleId });

      while (true) {
        await pic.tick(3);
        const httpRequests = await pic.getPendingHttpsOutcalls();
        if (httpRequests.length === 0) break;

        for (const request of httpRequests) {
          if (request.url.includes(API_FOOTBALL_URL)) {
            const mockData = createApiFootballResponse("8001", 1, 1);
            const responseBody = new TextEncoder().encode(JSON.stringify(mockData));

            await pic.mockPendingHttpsOutcall({
              requestId: request.requestId,
              subnetId: request.subnetId,
              response: {
                type: 'success',
                statusCode: 200,
                headers: [['Content-Type', 'application/json']],
                body: responseBody,
              },
            });
          }
        }
      }

      await (await fetchPromise)();

      const logResult2 = await (await oracleActor.icrc3_get_blocks([{
        start: 0n,
        length: 1000n
      }]))();
      const newBlockCount = logResult2.blocks.length;

      // Block count should be the same (no duplicate logged)
      expect(newBlockCount).toBe(initialBlockCount);
    });

    it('should create new ICRC-3 block when score changes', async () => {
      oracleActor.setIdentity(adminIdentity);

      const { oracleId } = await scheduleAndFetchMatch("9001", 0, 0);

      const logResult1 = await (await oracleActor.icrc3_get_blocks([{
        start: 0n,
        length: 1000n
      }]))();
      const initialBlockCount = logResult1.blocks.length;

      // Fetch with DIFFERENT score
      const fetchPromise = oracleActor.fetch_match_data({ oracleId });

      while (true) {
        await pic.tick(3);
        const httpRequests = await pic.getPendingHttpsOutcalls();
        if (httpRequests.length === 0) break;

        for (const request of httpRequests) {
          if (request.url.includes(API_FOOTBALL_URL)) {
            const mockData = createApiFootballResponse("9001", 1, 0); // Score changed!
            const responseBody = new TextEncoder().encode(JSON.stringify(mockData));

            await pic.mockPendingHttpsOutcall({
              requestId: request.requestId,
              subnetId: request.subnetId,
              response: {
                type: 'success',
                statusCode: 200,
                headers: [['Content-Type', 'application/json']],
                body: responseBody,
              },
            });
          }
        }
      }

      await (await fetchPromise)();

      const logResult2 = await (await oracleActor.icrc3_get_blocks([{
        start: 0n,
        length: 1000n
      }]))();
      const newBlockCount = logResult2.blocks.length;

      // Block count should increase (new block logged)
      expect(newBlockCount).toBeGreaterThan(initialBlockCount);
    });
  });

  describe("Monitored Leagues", () => {
    it('should get default monitored leagues (Premier League)', async () => {
      const leagues = await (await oracleActor.get_monitored_leagues())();

      expect(Array.isArray(leagues)).toBeTruthy();
      expect(leagues).toContain(39n); // Premier League ID
    });

    it('should allow admin to set monitored leagues', async () => {
      oracleActor.setIdentity(adminIdentity);

      const result = await (await oracleActor.set_monitored_leagues({
        leagueIds: [39n, 140n, 78n] // Premier League, La Liga, Bundesliga
      }))();

      expect("Ok" in result).toBeTruthy();

      const leagues = await (await oracleActor.get_monitored_leagues())();

      expect(leagues.length).toBe(3);
      expect(leagues).toContain(39n);
      expect(leagues).toContain(140n);
      expect(leagues).toContain(78n);
    });

    it('should REJECT set_monitored_leagues from non-admin', async () => {
      oracleActor.setIdentity(userIdentity);

      const result = await (await oracleActor.set_monitored_leagues({
        leagueIds: [39n]
      }))();

      expect("Error" in result).toBeTruthy();
      if ("Error" in result) {
        expect("Unauthorized" in result.Error).toBeTruthy();
      }
    });
  });

  describe("Scheduled Matches Query", () => {
    it('should return list of scheduled matches', async () => {
      oracleActor.setIdentity(adminIdentity);

      await scheduleAndFetchMatch("10001", 2, 1);

      const result = await (await oracleActor.get_scheduled_matches())();

      expect(Array.isArray(result)).toBeTruthy();
      expect(result.length).toBeGreaterThan(0);

      const match = result[0];
      expect(match).toHaveProperty("oracleId");
      expect(match).toHaveProperty("apiFootballId");
      expect(match).toHaveProperty("homeTeam");
      expect(match).toHaveProperty("awayTeam");
      expect(match).toHaveProperty("league");
      expect(match).toHaveProperty("status");
      expect(match).toHaveProperty("scheduledTime");
    });
  });

  describe("Supported Block Types", () => {
    it('should include oracle_event in supported block types', async () => {
      const blockTypes = await (await oracleActor.icrc3_supported_block_types())();

      expect(Array.isArray(blockTypes)).toBeTruthy();
      const oracleBlockType = blockTypes.find((bt: any) => bt.block_type === 'oracle_event');
      expect(oracleBlockType).toBeDefined();
      if (oracleBlockType) {
        expect(oracleBlockType.url).toBe('https://github.com/soccer-oracle');
      }
    });
  });
});