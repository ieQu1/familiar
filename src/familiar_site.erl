%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(familiar_site).

-behavior(gen_server).

%% API:
-export([ is_running/1
        , which_node/1
        , last_node/1

        , start/1
        , start/2
        , stop/1
        , stop/2

        , call/2
        , call/3
        , call/4
        , call/5
        ]).

%% behavior callbacks:
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% internal exports:
-export([ start_link/3
        ]).

-include_lib("snabbkaffe/include/trace.hrl").
-include("familiar_internal.hrl").

%%================================================================================
%% Type declarations
%%================================================================================

-define(familiar_unknown_event, familiar_unknown_event).

-define(call_via(CLUSTER, SITE), {?MODULE, CLUSTER, SITE}).

-record(call_is_running, {}).
-record(call_start, {opts :: map()}).
-record(call_stop, {}).
-record(call_last_node, {}).

%%================================================================================
%% API functions
%%================================================================================

%% @private
-spec start_link(
        familiar:site(),
        familiar:site_conf(),
        familiar_fixture:state()
       ) -> {ok, pid()}.
start_link({Cluster, Site}, Spec, FixtureState) ->
  gen_server:start_link(
    ?via(#fam_reg_site{cluster = Cluster, site = Site}),
    ?MODULE,
    [Cluster, FixtureState, Site, Spec],
    []).

%% @doc Is site running?
-spec is_running(familiar:site()) -> boolean().
is_running({ClusterId, SiteId}) ->
  gen_server:call(
    ?via(#fam_reg_site{cluster = ClusterId, site = SiteId}),
    #call_is_running{},
    infinity).

%% @doc Return current node name of the site.
%% Throws an error if site is not running.
-spec which_node(familiar:site()) -> node().
which_node(Site) ->
  case call_method(Site) of
    {erpc, Node} ->
      Node
  end.

%% @doc Get last node name used by the site.
%% It is equal to `familiar_site:which_node' if the site is currently running.
-spec last_node(familiar:site()) -> {ok, node()} | undefined.
last_node({ClusterId, SiteId}) ->
  gen_server:call(
    ?via(#fam_reg_site{cluster = ClusterId, site = SiteId}),
    #call_last_node{},
    infinity).

%% @doc Start the site if stopped.
%%
%% Can return `{error, already_running}'.
-spec start(familiar:site()) -> {ok, node()} | {error, _}.
start(Site) ->
  start(Site, #{}).

%% @doc Start the site if stopped, using `NodeName' as a prefix for the node.
%% Resulting node will be named `NodeName@Host'.
%%
%% Can return `{error, already_running}'.
-spec start(familiar:site(), peer:start_options()) -> {ok, node()} | {error, _}.
start({ClusterId, SiteId}, PeerOptions) ->
  gen_server:call(
    ?via(#fam_reg_site{cluster = ClusterId, site = SiteId}),
    #call_start{opts = PeerOptions},
    infinity).

-spec stop(familiar:cluster_id(), familiar:site_id()) -> ok.
stop(ClusterId, SiteId) ->
  stop({ClusterId, SiteId}).

%% @doc Stop the site's node.
%%
%% Note: this function doesn't destroy the site: it can be restarted later.
-spec stop(familiar:site()) -> ok.
stop({ClusterId, SiteId}) ->
  gen_server:call(
    ?via(#fam_reg_site{cluster = ClusterId, site = SiteId}),
    #call_stop{},
    infinity).

%% @doc Execute MFA on the site.
%% Site must be running.
-spec call(familiar:site() | node(), module(), atom(), list()) -> _.
call(Site, Module, Function, Args) ->
  call(Site, Module, Function, Args, 5_000).

%% @doc Execute MFA on the site.
%% Site must be running.
-spec call(familiar:site() | node(), module(), atom(), list(), timeout()) -> _.
call(Node, Module, Function, Args, Timeout) when is_atom(Node) ->
  erpc:call(Node, Module, Function, Args, Timeout);
call(Site, Module, Function, Args, Timeout) ->
  case call_method(Site) of
    {erpc, Node} ->
      erpc:call(Node, Module, Function, Args, Timeout)
  end.

-spec call(familiar:site() | node(), fun(() -> Ret)) -> Ret.
call(SiteOrNode, Fun) ->
  call(SiteOrNode, Fun, 5_000).

%% @doc Execute `Fun' on the site.
%% Site must be running.
-spec call(familiar:site() | node(), fun(() -> Ret), timeout()) -> Ret.
call(Node, Fun, Timeout) when is_atom(Node) ->
  erpc:call(Node, Fun, Timeout);
call(Site, Fun, Timeout) ->
  case call_method(Site) of
    {erpc, Node} ->
      erpc:call(Node, Fun, Timeout)
  end.

%%================================================================================
%% behavior callbacks
%%================================================================================

-record(s,
        { cluster            :: familiar:cluster_id()
        , site               :: familiar:site_id()
        , pid                :: pid() | undefined
        , name               :: atom()
        , node               :: node() | undefined
        , last_node          :: {ok, node()} | undefined
        , spec               :: familiar:cluster_conf()
        , fixture_state      :: familiar_fixture:state()
        , node_fixture_state :: map() | undefined
        , my_path            :: string()
        }).

%% @private
init([Cluster, FixtureState0, Site, SiteSpec]) ->
  process_flag(trap_exit, true),
  MyPath = filename:dirname(code:which(?MODULE)),
  ?tp(debug, familiar_site_init, SiteSpec),
  #{fixtures := Fixtures} = SiteSpec,
  case familiar_fixture:init_per_site(Fixtures, {Cluster, Site}, FixtureState0) of
    {ok, FixtureState} ->
      {ok, #s{ cluster       = Cluster
             , site          = Site
             , spec          = SiteSpec
             , fixture_state = FixtureState
             , my_path       = MyPath
             }};
    {error, Reason} ->
      {stop, Reason}
  end.

%% @private
handle_call(#call_start{opts = StartOpts}, _From, S0 = #s{pid = Pid}) ->
  case Pid of
    undefined ->
      case do_start(StartOpts, S0) of
        {ok, Node, S} ->
          {reply, {ok, Node}, S};
        {error, _} = Err ->
          {reply, Err, S0}
      end;
    _ when is_pid(Pid) ->
      {reply, {error, already_started}, S0}
  end;
handle_call(#call_stop{}, _From, S0 = #s{pid = Pid}) ->
  case Pid of
    undefined ->
      {reply, ok, S0};
    _ when is_pid(Pid) ->
      {ok, S} = do_stop(S0),
      {reply, ok, S}
  end;
handle_call(#call_is_running{}, _From, S = #s{pid = Pid}) ->
  Reply = is_pid(Pid) andalso is_process_alive(Pid),
  {reply, Reply, S};
handle_call(#call_last_node{}, _From, S = #s{last_node = LastNode}) ->
  {reply, LastNode, S};
handle_call(Call, From, S) ->
  ?tp(warning, ?familiar_unknown_event,
      #{ kind => call
       , from => From
       , content => Call
       , server => ?MODULE
       }),
  {reply, {error, unknown_call}, S}.

%% @private
handle_cast(Cast, S) ->
  ?tp(warning, ?familiar_unknown_event,
      #{ kind => cast
       , content => Cast
       , server => ?MODULE
       }),
  {noreply, S}.

%% @private
handle_info({'EXIT', Pid, Reason}, S = #s{pid = Pid}) ->
  {stop, {unexpected_peer_stop, Reason}, S};
handle_info({'EXIT', _, shutdown}, S) ->
  {stop, shutdown, S};
handle_info(Info, S) ->
  ?tp(warning, ?familiar_unknown_event,
      #{ kind => info
       , content => Info
       , server => ?MODULE
       }),
  {noreply, S}.

%% @private
terminate(Reason, S0 = #s{cluster = Cluster, site = Site, spec = Spec, fixture_state = FS}) ->
  Success = not familiar_cluster:isfail(Cluster),
  ?tp(debug, ?familiar_site_terminate, #{success => Success, cluster => Cluster, site => Site}),
  familiar_lib:is_normal_exit(Reason) orelse
    ?tp(warning, ?familiar_abnormal_exit,
        #{ server => ?MODULE
         , reason => Reason
         }),
  _ = do_stop(S0),
  #{fixtures := Fixtures} = Spec,
  familiar_fixture:cleanup_per_site(Fixtures, {Cluster, Site}, Success, FS),
  ?tp(familiar_test_site_destroyed, #{site => Site});
terminate(_Reason, _) ->
  ok.

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================

do_start(CustomOpts, S0) ->
  #s{ cluster = Cluster
    , site = Site
    , spec = #{ fixtures := Fixtures
              , peer     := DefaultPeerOpts
              }
    , fixture_state = FS
    , my_path = MyPath
    } = S0,
  #{ args := Args0
   } = PeerOpts0 = maps:merge(DefaultPeerOpts, CustomOpts),
  MandatoryArgs = [ "-pz", MyPath
                  , "-setcookie", atom_to_list(erlang:get_cookie())
                  ],
  PeerOpts = PeerOpts0#{args => Args0 ++ MandatoryArgs},
  ?tp(debug, familiar_test_site_start, #{site => Site, peer => PeerOpts}),
  {ok, Pid, Node} = peer:start_link(PeerOpts),
  S = S0#s{ pid = Pid
          , node = Node
          , last_node = {ok, Node}
          },
  persistent_term:put(?call_via(Cluster, Site), {erpc, Node}),
  case familiar_fixture:init_per_node(Fixtures, {Cluster, Site}, Node, FS) of
    {ok, NFS} ->
      {ok, Node, S#s{node_fixture_state = NFS}};
    {error, _} = Err ->
      {ok, _} = do_stop(S),
      Err
  end.

do_stop(S = #s{pid = undefined}) ->
  {ok, S};
do_stop(S) ->
  #s{ spec = #{id := Cluster, fixtures := Fixtures}
    , cluster = Cluster
    , site = Site
    , pid = Pid
    , node = Node
    , node_fixture_state = NFS
    } = S,
  is_map(NFS) andalso
    familiar_fixture:cleanup_per_node(Fixtures, {Cluster, Site}, Node, NFS),
  persistent_term:erase(?call_via(Cluster, Site)),
  unlink(Pid),
  peer:stop(Pid),
  ?tp(debug, familiar_test_site_stop, #{site => Site}),
  {ok, S#s{ pid = undefined
          , node = undefined
          , name = undefined
          , node_fixture_state = undefined
          }}.

call_method({ClusterId, SiteId} = Site) ->
  case persistent_term:get(?call_via(ClusterId, SiteId), undefined) of
    undefined ->
      error({site_is_not_running, Site});
    Other ->
      Other
  end.
