// Consensus algorithm for validating match data from multiple sources
import Buffer "mo:base/Buffer";
import D "mo:base/Debug";
import Nat "mo:base/Nat";

module {
  public type Score = {
    home : Nat;
    away : Nat;
  };

  public type ConsensusResult = {
    home : Nat;
    away : Nat;
    agreeing : [Text];
  };

  /// Achieve consensus from multiple API results
  /// Requires at least 2 out of 3 APIs to agree on the score
  public func achieve(
    results : [(Text, ?Score)]
  ) : ?ConsensusResult {
    let validResults = Buffer.Buffer<(Text, Score)>(3);

    // Filter out null results
    for ((provider, result) in results.vals()) {
      switch (result) {
        case (?r) { validResults.add((provider, r)) };
        case (null) {};
      };
    };

    let valid = Buffer.toArray(validResults);
    if (valid.size() < 2) {
      return null; // Need at least 2 valid responses
    };

    // Check if at least 2 results agree
    for (i in valid.keys()) {
      let agreeing = Buffer.Buffer<Text>(3);
      let (provider1, score1) = valid[i];
      agreeing.add(provider1);

      for (j in valid.keys()) {
        if (i != j) {
          let (provider2, score2) = valid[j];
          if (score1.home == score2.home and score1.away == score2.away) {
            agreeing.add(provider2);
          };
        };
      };

      if (agreeing.size() >= 2) {
        return ?{
          home = score1.home;
          away = score1.away;
          agreeing = Buffer.toArray(agreeing);
        };
      };
    };

    null; // No consensus achieved
  };
};
