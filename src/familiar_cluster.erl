%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(familiar_cluster).

-behavior(gen_server).

%% API:
-export([start_link/2, create_site/3, stop/2]).

%% behavior callbacks:
-export([init/1, handle_continue/2, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% internal exports:
-export([merge_conf/2]). %% TODO: remove

-export_type([conf/0]).

-include("familiar_internal.hrl").

%%================================================================================
%% Type declarations
%%================================================================================

-record(call_create_site,
        { site :: familiar:site_id()
        , conf :: familiar:site_conf()
        }).

-type conf() ::
        #{ id := familiar:cluster_id()
         , fixtures := [familiar_fixture:t()]
         , peer := peer:start_options()
         , net := {byte(), byte(), byte(), byte()}
         , subnet := 0..32
         }.

%%================================================================================
%% API functions
%%================================================================================

-spec start_link(pid(), conf()) -> {ok, pid()}.
start_link(Parent, Conf = #{id := ID}) ->
  gen_server:start_link(
    ?via(#fam_reg_cluster_man{cluster = ID}),
    ?MODULE,
    [Parent, Conf],
    []).

-spec stop(familiar:cluster_id(), term()) -> ok.
stop(ID, Reason) ->
  familiar_lib:sync_stop_proc(
    gproc:where(?name(#fam_reg_cluster_sup{cluster = ID})),
    Reason,
    5_000).

-spec create_site(familiar:cluster_id(), familiar:site_id(), familiar:site_conf()) -> {ok, familiar:site()} | {error, _}.
create_site(Cluster, Site, Conf) ->
  gen_server:call(
    ?via(#fam_reg_cluster_man{cluster = Cluster}),
    #call_create_site{site = Site, conf = Conf}).

%%================================================================================
%% behavior callbacks
%%================================================================================

-record(s,
        { id
        , conf
        , sites = #{} :: #{familiar:site_id() => non_neg_integer()}
        , fstate
        , parent_sup
        , site_sup
        , success = true :: boolean()
        , n_sites = 0
        , net
        , subnet
        }).

init([Parent, Conf]) ->
  process_flag(trap_exit, true),
  maybe
    #{ id       := ClusterId
     , fixtures := Fixtures
     , net      := Net
     , subnet   := SubNet
     } ?= Conf,
    {ok, FixtureState} ?= familiar_fixture:init_per_cluster(ClusterId, Fixtures),
    S = #s{ parent_sup = Parent
          , conf       = Conf
          , fstate     = FixtureState
          , id         = ClusterId
          , net        = Net
          , subnet     = SubNet
          },
    {ok, S, {continue, get_sup}}
  else
    Err ->
      {error, {badarg, Err}}
  end.

handle_continue(get_sup, S = #s{parent_sup = ParentSup}) ->
  Children = supervisor:which_children(ParentSup),
  {_, Pid, _, _} = lists:keyfind(sites, 1, Children),
  true = is_pid(Pid),
  {noreply, S#s{site_sup = Pid}}.

handle_call(#call_create_site{site = SiteId, conf = Conf}, _From, S0) ->
  case do_create_site(S0, SiteId, Conf) of
    {ok, Site, S} ->
      {reply, Site, S};
    Err ->
      {reply, Err, S0}
  end;
handle_call(_Call, _From, S) ->
  {reply, {error, unknown_call}, S}.

handle_cast(_Cast, S) ->
  {noreply, S}.

handle_info({'EXIT', _, Reason}, S) ->
  ?tp(warning, "Recv exit", #{}),
  {stop, Reason, S};
handle_info(_Info, S) ->
  {noreply, S}.

terminate(_Reason, #s{fstate = FState, conf = Conf, success = Success}) ->
  ?tp(warning, "Terminating cluster", #{}),
  #{id := ClusterId, fixtures := Fixtures} = Conf,
  familiar_fixture:cleanup_per_cluster(
    ClusterId,
    Fixtures,
    Success,
    FState),
  ok.

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================

do_create_site(S, SiteId, CustomSiteSpec) ->
  #s{ id = ClusterId
    , n_sites = NSites
    , sites = Sites
    , conf = CommonSpec
    , fstate = FixtureState
    , site_sup = SiteSup
    } = S,
  SiteN = NSites,
  Site = {ClusterId, SiteId},
  maybe
    ok ?= case Sites of
            #{SiteId := _} -> {error, {already_exists, SiteId}};
            #{} -> ok
          end,
    {ok, NodeName} ?= derive_name(SiteId, CustomSiteSpec, SiteN),
    {ok, DefaultSiteSpec} ?= default_site_specific_opts(S, SiteId, SiteN, NodeName),
    SiteSpec = lists:foldr(
                 fun merge_conf/2,
                 #{},
                 [ CommonSpec
                 , DefaultSiteSpec
                 , CustomSiteSpec
                 ]),
    {ok, _} ?= familiar_sup:start_site(SiteSup, Site, SiteSpec, FixtureState),
    { ok
    , Site
    , S#s{ n_sites = NSites + 1
         , sites = Sites#{SiteId => SiteN}
         }
    }
  end.

default_site_specific_opts(#s{net = Net, subnet = SubNet}, _Site, SiteN, NodeName) ->
  maybe
    {ok, Address} ?= familiar_lib:get_ip_addr(Net, SubNet, SiteN),
    Host = inet:ntoa(Address),
    {ok, #{peer =>
             #{ host => Host
              , name => NodeName
              }}}
  end.

%% @doc Merge cluster configuration.
-spec merge_conf(familiar:cluster_conf(), familiar:cluster_conf()) -> familiar:cluster_conf().
merge_conf(C1, C2) ->
  maps:merge_with(
    fun(fixtures, A, B) ->
        A ++ B;
       (peer, A, B) ->
        maps:merge(A, B)
    end,
    C1,
    C2).

derive_name(_Site, Spec = #{peer := #{name := Name}}, _SiteN) ->
  case is_atom(Name) of
    true ->
      {ok, Spec};
    false ->
      {error, {bad_name, Name}}
  end;
derive_name(Site, _Spec, _SiteN) when is_atom(Site) ->
  {ok, Site};
derive_name(Site, _Spec, _SiteN) when is_binary(Site) ->
  {ok, binary_to_atom(Site)};
derive_name(_Site, _Spec, SiteN) ->
  {error, <<"site", (integer_to_binary(SiteN))/binary>>}.
