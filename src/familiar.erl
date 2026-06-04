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
        , ensure_distr/1
        ]).

-export_type([cluster_id/0, site_id/0, site/0, cluster_conf/0, site_conf/0]).

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
        #{ peer => peer:start_options()
         , start => boolean()
         }.

%%================================================================================
%% API
%%================================================================================

-spec start_link_cluster(cluster_conf()) -> ok | {error, _}.
start_link_cluster(Conf0) ->
  maybe
    {ok, Conf} ?= with_defaults(Conf0),
    {ok, _} = application:ensure_all_started(familiar),
    %% TODO: check if short names are used
    ok = ensure_distr(#{}),
    {ok, Sup} = familiar_sup:start_cluster(Conf),
    link(Sup),
    ok
  end.

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

%%================================================================================
%% Internal functions
%%================================================================================

ensure_epmd() ->
    open_port({spawn, "epmd"}, []).

-spec with_defaults(cluster_conf()) -> {ok, familiar_cluster:conf()} | {error, _}.
with_defaults(Conf) when is_map(Conf) ->
  maybe
    {ok, Id} ?= verify_id(Conf),
    {ok, Fixtures} ?= verify_fixtures(Conf),
    {ok, Net, SubNet} ?= verify_net(Conf),
    {ok, Peer} ?= verify_peer(Conf),
    {ok,
     #{ id => Id
      , fixtures => Fixtures
      , peer => Peer
      , net => Net
      , subnet => SubNet
      }}
  end;
with_defaults(_Conf) ->
  {error, badarg}.

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
