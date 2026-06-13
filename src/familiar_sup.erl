%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @private A process that manages test clusters.
%%
%% Cluster configuration:
%% <itemize>
%% <li>`peer': <a href="https://www.erlang.org/doc/apps/stdlib/peer.html#t:start_options/0">peer</a> start options.
%% Optional.</li>
%% <li>`fixtures': list of {@link familiar_fixture . fixtures}.
%% Mandatory.</li>
%% </itemize>
-module(familiar_sup).

-behavior(supervisor).

%% API:
-export([start_link_top/0, start_cluster/1, stop_cluster/1, start_site/4]).

%% behavior callbacks:
-export([init/1]).

%% internal exports:
-export([ start_link_sites_sup/1
        , start_link_cluster/1
        ]).

-include("familiar_internal.hrl").

%%================================================================================
%% Type declarations
%%================================================================================

-define(top, familiar_sup).

-define(pt_success, familiar_sup_success).

%%================================================================================
%% API functions
%%================================================================================

-spec start_link_top() -> supervisor:startlink_ret().
start_link_top() ->
  supervisor:start_link({local, ?top}, ?MODULE, top).

-spec start_link_cluster(familiar_cluster:conf()) -> supervisor:startlink_ret().
start_link_cluster(Conf = #{id := ID}) ->
  supervisor:start_link(
    ?via(#fam_reg_cluster_sup{cluster = ID}),
    ?MODULE,
    {cluster, Conf}).

-spec start_link_sites_sup(familiar:cluster_id()) -> supervisor:startlink_ret().
start_link_sites_sup(ID) ->
  supervisor:start_link(
    ?via(#fam_reg_cluster_sites_sup{cluster = ID}),
    ?MODULE,
    sites).

-spec start_cluster(familiar:cluster_conf()) -> supervisor:startlink_ret().
start_cluster(Conf) ->
  supervisor:start_child(?top, [Conf]).

-spec stop_cluster(pid()) -> ok.
stop_cluster(Pid) ->
  supervisor:terminate_child(?top, Pid).

%% @doc Create a site, if not created yet.
%% Note: this function doesn't start the site.
-spec start_site(
        pid(),
        familiar:site(),
        map(),
        familiar_fixture:state()
       ) -> {ok, pid()} | {error, _}.
start_site(Sup, Site, Conf, FixtureState) ->
  supervisor:start_child(Sup, [Site, Conf, FixtureState]).

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% behavior callbacks
%%================================================================================

%% @private
init(top) ->
  SupFlags = #{ strategy      => simple_one_for_one
              , intensity     => 100
              , period        => 1
              },
  Children = #{ id       => cluster
              , type     => supervisor
              , start    => {?MODULE, start_link_cluster, []}
              , shutdown => infinity
              , restart  => temporary
              },
  {ok, {SupFlags, [Children]}};
init({cluster, Conf}) ->
  #{id := ID} = Conf,
  SupFlags = #{ strategy      => one_for_all
              , intensity     => 0
              , period        => 10
              , auto_shutdown => never
              },
  Children = [ #{ id       => cluster_manager
                , type     => worker
                , restart  => permanent
                , start    => {familiar_cluster, start_link, [self(), Conf]}
                , shutdown => 5_000
                }
             , #{ id       => sites
                , type     => supervisor
                , restart  => permanent
                , start    => {?MODULE, start_link_sites_sup, [ID]}
                , shutdown => infinity
                }
             ],
  {ok, {SupFlags, Children}};
init(sites) ->
  SupFlags = #{ strategy      => simple_one_for_one
              , intensity     => 10
              , period        => 1
              , auto_shutdown => never
              },
  Children = #{ id       => peer
              , type     => worker
              , start    => {familiar_site, start_link, []}
              , shutdown => 15_000
              , restart  => transient
              },
  {ok, {SupFlags, [Children]}}.

%%================================================================================
%% Internal functions
%%================================================================================
