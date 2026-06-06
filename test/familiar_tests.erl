%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(familiar_tests).

-include_lib("eunit/include/eunit.hrl").
-include("familiar.hrl").

%%================================================================================
%% Tests
%%================================================================================

-define(timeout, 10_000).

start_stop_test_() ->
  {timeout, ?timeout,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(ok, familiar:start_link_cluster(#{id => Cluster})),
       ?assertEqual(ok, familiar:stop_cluster(Cluster, true))
   end}.

badconf_test_() ->
  {timeout, ?timeout,
   fun() ->
       ?assertMatch(
          {error, badarg},
          familiar:start_link_cluster(foo)),
       ?assertMatch(
          {error, bad_cluster_id},
          familiar:start_link_cluster(#{})),
       ?assertMatch(
          {error, {bad_fixtures, _}},
          familiar:start_link_cluster(#{id => foo, fixtures => 1}))
   end}.

simple_test_() ->
  {timeout, ?timeout,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(
          ok,
          familiar:start_link_cluster(#{ id => Cluster
                                       , net => {127, 31, 0, 0}
                                       , subnet => 16
                                       })),
       {ok, S1} = familiar:create_site(Cluster, site1),
       ?assertEqual(
          {ok, 'site1@127.31.0.0'},
          familiar:start_site(S1)),
       ?assertEqual(
          'site1@127.31.0.0',
          familiar_site:call(S1, erlang, node, [])),
       ?assertEqual(
          'site1@127.31.0.0',
          ?ON(S1, erlang:node())),
       {ok, S2, 'site2@127.31.0.1'} =
         familiar:create_site(Cluster, site2, #{start => true}),
       ?assertEqual(
          'site2@127.31.0.1',
          ?ON(S2, erlang:node())),
       ?assertEqual(
          ok,
          familiar:stop_cluster(Cluster, true))
   end}.

is_running_test_() ->
  {timeout, ?timeout,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(ok, familiar:start_link_cluster(#{id => Cluster})),
       {ok, S1} = familiar:create_site(Cluster, site1),
       %% Stopped:
       ?assertNot(familiar:is_running(S1)),
       %% Started:
       ?assertMatch({ok, _}, familiar:start_site(S1)),
       ?assert(familiar:is_running(S1)),
       %% Stopped again:
       ?assertEqual(ok, familiar:stop_site(S1)),
       ?assertNot(familiar:is_running(S1))
   end}.

which_node_test_() ->
  {timeout, ?timeout,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(
          ok,
          familiar:start_link_cluster(#{ id => Cluster
                                       , net => {127, 31, 0, 0}
                                       , subnet => 16
                                       })),
       {ok, S1} = familiar:create_site(Cluster, site1),
       %% Stopped, never ran:
       ?assertError({site_is_not_running, _}, familiar:which_node(S1)),
       ?assertEqual(undefined, familiar:last_node(S1)),
       %% Running:
       {ok, Node1} = familiar:start_site(S1),
       ?assertEqual(Node1, familiar:which_node(S1)),
       ?assertEqual({ok, Node1}, familiar:last_node(S1)),
       %% Stopped again:
       ?assertEqual(ok, familiar:stop_site(S1)),
       ?assertError({site_is_not_running, _}, familiar:which_node(S1)),
       ?assertEqual({ok, Node1}, familiar:last_node(S1)),
       %% Restarted with a different node name:
       {ok, Node2} = familiar:start_site(S1, #{peer => #{name => new_name}}),
       ?assertEqual('new_name@127.31.0.0', Node2),
       ?assertEqual(Node2, familiar:which_node(S1)),
       ?assertEqual({ok, Node2}, familiar:last_node(S1)),
       %% Stopped again:
       ?assertEqual(ok, familiar:stop_site(S1)),
       ?assertError({site_is_not_running, _}, familiar:which_node(S1)),
       ?assertEqual({ok, Node2}, familiar:last_node(S1))
   end}.

call_test_() ->
  {timeout, ?timeout,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(ok, familiar:start_link_cluster(#{id => Cluster})),
       {ok, S1, Node} = familiar:create_site(Cluster, site1, #{start => true}),
       %% Running, normal call:
       ?assertEqual(Node, familiar:call(S1, fun() -> erlang:node() end)),
       ?assertEqual(Node, familiar:call(S1, fun() -> erlang:node() end, 1_000)),
       ?assertEqual(Node, familiar:call(S1, erlang, node, [])),
       ?assertEqual(Node, familiar:call(S1, erlang, node, [], 1_000)),
       %% Stopped:
       ?assertEqual(ok, familiar:stop_site(S1)),
       ?assertError({site_is_not_running, _}, familiar:call(S1, fun() -> erlang:node() end)),
       ?assertError({site_is_not_running, _}, familiar:call(S1, fun() -> erlang:node() end, 1_000)),
       ?assertError({site_is_not_running, _}, familiar:call(S1, erlang, node, [])),
       ?assertError({site_is_not_running, _}, familiar:call(S1, erlang, node, [], 1_000))
   end}.

setfail_test_() ->
  {timeout, ?timeout,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(ok, familiar:start_link_cluster(#{id => Cluster})),
       ?assertNot(familiar_cluster:isfail(Cluster)),
       {ok, _S1, _Node} = familiar:create_site(Cluster, site1, #{start => true}),
       ?assertEqual(ok, familiar_cluster:set_fail(Cluster)),
       ?assert(familiar_cluster:isfail(Cluster))
   end}.

%%================================================================================
%% Internal functions
%%================================================================================
