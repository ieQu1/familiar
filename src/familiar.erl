%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(familiar).

-export([ start_link_cluster/1
        , stop_cluster/2
        , create_site/3
        , create_site/2
        , start_site/1
        , start_site/2
        , which_node/1
        , is_running/1
        , last_node/1
        , stop_site/1
        , stop_site/2
        , ensure_distr/1
        , default_fixtures/0

        , call/2
        , call/3
        , call/4
        , call/5
        ]).

-export_type([cluster_id/0, site_id/0, site/0, cluster_conf/0, site_conf/0]).

%% Internal exports
-export([cluster_proxy_entrypoint/2]).

-include_lib("snabbkaffe/include/trace.hrl").
-include("familiar_internal.hrl").

-ifdef(TEST).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.

%%================================================================================
%% Type declarations
%%================================================================================

-type site_id() :: term().

-type cluster_id() :: term().

-type site() :: {cluster_id(), site_id()}.

-type cluster_conf() ::
        #{ id       := cluster_id()
         , fixtures => [familiar_fixture:t()]
         , peer     => peer:start_options()
         , net      => {byte(), byte(), byte(), byte()}
         , subnet   => 0..32
         , _        => _
         }.

-type site_conf() ::
        #{ fixtures => [familiar_fixture:t()]
         , peer     => peer:start_options()
         , start    => boolean()
         }.

%%================================================================================
%% API
%%================================================================================

-spec start_link_cluster(cluster_conf()) -> ok | {error, _}.
start_link_cluster(Conf) ->
  proc_lib:start_link(?MODULE, cluster_proxy_entrypoint, [self(), Conf]).

-spec stop_cluster(cluster_id(), boolean()) -> ok.
stop_cluster(ClusterId, Success) when is_boolean(Success) ->
  familiar_cluster:stop(ClusterId, Success).

-spec create_site(cluster_id(), site_id()) -> ok | {error, _}.
create_site(Cluster, Site) ->
  create_site(Cluster, Site, #{}).

-spec create_site(cluster_id(), site_id(), site_conf()) -> {ok, site()} | {ok, site(), node()} | {error, _}.
create_site(Cluster, SiteId, SiteConf0) ->
  case maps:take(start, SiteConf0) of
    {Start, SiteConf} ->
      ok;
    error ->
      Start = false,
      SiteConf = SiteConf0
  end,
  case familiar_cluster:create_site(Cluster, SiteId, SiteConf) of
    {ok, Site} ->
      case Start of
        false ->
          {ok, Site};
        true ->
          case start_site(Site, maps:get(peer, SiteConf, #{})) of
            {ok, Node} ->
              {ok, Site, Node};
            {error, _} = Err ->
              Err
          end
      end;
    {error, _} = Err ->
      Err
  end.

-spec start_site(site()) -> {ok, node()} | {error, _}.
start_site(Site) ->
  familiar_site:start(Site).

-spec start_site(site(), peer:start_options()) -> {ok, node()} | {error, _}.
start_site(Site, Options) ->
  familiar_site:start(Site, Options).

-spec is_running(site()) -> boolean().
is_running(Site) ->
  familiar_site:is_running(Site).

%% @doc Return current node name of the site.
%% Throws an error if site is not running.
-spec which_node(site()) -> node().
which_node(Site) ->
  familiar_site:which_node(Site).

%% @doc Get last node name used by the site.
%% It is equal to `familiar_site:which_node' if the site is currently running.
-spec last_node(site()) -> {ok, node()} | undefined.
last_node(Site) ->
  familiar_site:last_node(Site).

%% @doc Stop the site's node.
%%
%% Note: this function doesn't destroy the site: it can be restarted later.
-spec stop_site(site()) -> ok.
stop_site(Site) ->
  familiar_site:stop(Site).

-spec stop_site(cluster_id(), site_id()) -> ok.
stop_site(Cluster, Site) ->
  familiar_site:stop({Cluster, Site}).

-spec ensure_distr(#{name => atom(), _ => _}) -> ok.
ensure_distr(Opts0) ->
  case maps:take(name, Opts0) of
    {Name, Opts} ->
      ok;
    error ->
      Opts = Opts0,
      Name = 'conjurer@127.0.0.1'
  end,
  ensure_epmd(),
  case net_kernel:start(Name, Opts) of
    {ok, _Pid} ->
      ok;
    {error, {already_started, _}} ->
      ok;
    Err ->
      Err
  end.

-spec default_fixtures() -> [familiar_fixture:t()].
default_fixtures() ->
  familiar_fixture:defaults().

-spec call(site(), fun(() -> Ret)) -> Ret.
call(Site, Fun) when is_function(Fun, 0) ->
  familiar_site:call(Site, Fun).

%% @doc Execute `Fun' on the site.
%% Site must be running.
-spec call(familiar:site(), fun(() -> Ret), timeout()) -> Ret.
call(Site, Fun, Timeout) when is_function(Fun, 0) ->
  familiar_site:call(Site, Fun, Timeout).

%% @doc Execute Module:Function(Args) on Site.
-spec call(familiar:site() | node(), module(), atom(), list()) -> _.
call(Site, Module, Function, Args) when is_atom(Module), is_atom(Function), is_list(Args) ->
  familiar_site:call(Site, Module, Function, Args).

%% @doc Execute Module:Function(Args) on Site with Timeout.
-spec call(familiar:site() | node(), module(), atom(), list(), timeout()) -> _.
call(Site, Module, Function, Args, Timeout) when is_atom(Module), is_atom(Function), is_list(Args) ->
  familiar_site:call(Site, Module, Function, Args, Timeout).

%%================================================================================
%% Internal exports
%%================================================================================

-spec cluster_proxy_entrypoint(pid(), familiar:cluster_conf()) -> no_return().
cluster_proxy_entrypoint(Parent, Conf0) ->
  process_flag(trap_exit, true),
  maybe
    {ok, Conf} ?= with_defaults(Conf0),
    #{id := ClusterId, auto_shutdown := AutoShutdown} = Conf,
    {ok, _} = application:ensure_all_started(familiar),
    %% TODO: check if short names are used
    ok = ensure_distr(#{}),
    {ok, Sup} = familiar_sup:start_cluster(Conf),
    link(Sup),
    proc_lib:init_ack(Parent, ok),
    proxy_loop(ClusterId, AutoShutdown, Parent, Sup)
  else
    Err ->
      proc_lib:init_ack(Parent, Err)
  end.

%%================================================================================
%% Internal functions
%%================================================================================

proxy_loop(ClusterId, AutoShutdown, Parent, Sup) ->
  receive
    {'EXIT', Sup, Reason} ->
      case familiar_lib:is_normal_exit(Reason) of
        true ->
          ok;
        false ->
          exit(Reason)
      end;
    {'EXIT', Parent, Reason} when AutoShutdown ->
      Success = familiar_lib:is_normal_exit(Reason),
      ?tp(info, familiar_cluster_shut_down, #{cluster => ClusterId, success => Success}),
      stop_cluster(ClusterId, Success);
    {'EXIT', Parent, _} ->
      ok;
    Msg ->
      ?tp(info, ?familiar_unknown_event,
          #{ server  => cluster_proxy
           , cluster => ClusterId
           , event   => Msg
           , parent  => Parent
           , sup     => Sup
           }),
      proxy_loop(ClusterId, AutoShutdown, Parent, Sup)
  end.

ensure_epmd() ->
  open_port({spawn, "epmd"}, []).

-spec with_defaults(cluster_conf()) -> {ok, familiar_cluster:conf()} | {error, _}.
with_defaults(Conf) when is_map(Conf) ->
  maybe
    {ok, AutoShutdown} ?= verify_auto_shutdown(Conf),
    {ok, Id} ?= verify_id(Conf),
    {ok, Fixtures} ?= verify_fixtures(Conf),
    {ok, Net, SubNet} ?= verify_net(Conf),
    {ok, Peer} ?= verify_peer(Conf),
    {ok,
     #{ id            => Id
      , auto_shutdown => AutoShutdown
      , fixtures      => Fixtures
      , peer          => Peer
      , net           => Net
      , subnet        => SubNet
      }}
  end;
with_defaults(_Conf) ->
  {error, badarg}.

verify_auto_shutdown(#{auto_shutdown := AS}) ->
  if is_boolean(AS) ->
      {ok, AS};
     true ->
      {error, bad_auto_shutdown}
  end;
verify_auto_shutdown(#{}) ->
  {ok, true}.

verify_id(#{id := Id}) when Id =/= undefined ->
  {ok, Id};
verify_id(_) ->
  {error, bad_cluster_id}.

verify_net(Conf) ->
  Net = maps:get(net, Conf, {127, 22, 0, 0}),
  SubNet = maps:get(subnet, Conf, 24),
  case inet:ntoa(Net) of
    {error, einval} ->
      {error, {bad_net, Net}};
    _ when is_integer(SubNet) andalso SubNet >=0 andalso SubNet < 32 ->
      {ok, Net, SubNet};
    _ ->
      {error, {bad_subnet, SubNet}}
  end.

verify_fixtures(#{fixtures := L}) ->
  Ok = is_list(L) andalso lists:all(
                            fun({Mod, Conf}) when is_atom(Mod), is_map(Conf) ->
                                true;
                               (_) ->
                                false
                            end,
                            L),
  case Ok of
    true -> {ok, L};
    false -> {error, {bad_fixtures, L}}
  end;
verify_fixtures(#{}) ->
  {ok, familiar_fixture:defaults()}.

verify_peer(Conf) ->
  DefaultPeerConf = #{ longnames => true
                     , peer_down => stop
                     , shutdown => 4_000
                     , args => ["+S", "1:1"]
                     },
  CustomPeerConf = maps:get(peer, Conf, #{}),
  case is_map(CustomPeerConf) of
    true ->
      {ok, maps:merge(DefaultPeerConf, CustomPeerConf)};
    false ->
      {error, {bad_peer_conf, CustomPeerConf}}
  end.

-ifdef(TEST).

verify_conf_test_() ->
  {timeout, 15_000,
   ?_assert(proper:quickcheck(verify_cluster_conf_prop()))}.

cluster_conf() ->
  oneof(
    [ term()
    , map()
    , ?LET({Id, AS, Fix, Peer, Net, SubNet}, {term(), term(), term(), map(), term(), term()},
           #{ id => term()
            , auto_shutdown => term()
            , fixtures => list()
            , peer => map()
            , net => tuple()
            , subnet => number()
            })
    ]).

verify_cluster_conf_prop() ->
  ?FORALL(T, cluster_conf(),
          case with_defaults(T) of
            {ok, #{id := _, fixtures := _, peer := #{}, net := _, subnet := _}}  ->
              true;
            {error, _} ->
              true;
            Ret ->
              error({T, '->', Ret})
          end).

-endif.
