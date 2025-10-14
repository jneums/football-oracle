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

  public type HttpRequest = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [HttpHeader];
    body : ?Blob;
    method : HttpMethod;
    transform : ?TransformContext;
  };

  public type HttpResponse = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };

  public type IC = actor {
    http_request : HttpRequest -> async HttpResponse;
  };

  public type Score = {
    home : Nat;
    away : Nat;
  };
};
