%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(familiar_tests).

-include_lib("eunit/include/eunit.hrl").
-include("familiar.hrl").

%%================================================================================
%% Tests
%%================================================================================

start_stop_test_() ->
  {timeout, 10_000,
   fun() ->
       Cluster = ?FUNCTION_NAME,
       ?assertEqual(
          ok,
          familiar:start_link_cluster(#{ id => Cluster
                                       , net => {127, 31, 0, 0}
                                       , subnet => 16
                                       })),
       ?assertEqual(
          ok,
          familiar:stop_cluster(Cluster, true))
   end}.

simple_test_() ->
  {timeout, 10_000,
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

%%================================================================================
%% Internal functions
%%================================================================================
