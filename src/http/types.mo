// HTTP types for making outcalls
module {
  public type HttpHeader = {
    name : Text;
    value : Text;
  };

  public type HttpMethod = {
    #get;
  };

  public type TransformArgs = {
    response : HttpResponse;
    context : Blob;
  };

  public type TransformContext = {
    function : shared query TransformArgs -> async HttpResponse;
    context : Blob;
  };

  public type HttpResponse = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };

  public type MatchStatus = {
    #NotStarted; // NS, TBD, etc.
    #InProgress; // 1H, HT, 2H, ET, P, LIVE, etc.
    #Finished; // FT, AET, PEN
    #Postponed; // PST
    #Cancelled; // CANC
    #Abandoned; // ABD
    #Unknown;
  };

  public type Score = {
    home : Nat;
    away : Nat;
    status : MatchStatus;
  };
};
