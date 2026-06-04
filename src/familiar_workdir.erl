%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @doc A test fixture that creates and optionally destroys the working directories of the sites.
%%
%% By default, working directories are deleted when the cluster is stopped with reason
%% `shutdown' or `normal'.
%%
%% This behavior can be overridden by setting a Linux environment variable `FAMILIAR_WORKDIR_CLEANUP':
%% <itemize>
%% <li>`true': Always delete</li>
%% <li>`false': Never delete</li>
%% <li>Other: default behavior</li>
%% </itemize>
%%
%% Configuration:
%% <itemize>
%% <li>`testcase': Name of the testcase or any other unique atom identifying the cluster.
%% Mandatory.</li>
%% </itemize>
-module(familiar_workdir).

-behavior(familiar_fixture).

%% API:
-export([]).

%% behavior callbacks:
-export([ init_per_cluster/3
        , cleanup_per_cluster/4
        , init_per_site/3
        , init_per_node/4
        ]).

-export_type([conf/0]).

%%================================================================================
%% Type declarations
%%================================================================================

-type conf() ::
        #{
         }.

%%================================================================================
%% API functions
%%================================================================================

%%================================================================================
%% behavior callbacks
%%================================================================================

%% @private
init_per_cluster(ClusterId, _Conf, State) ->
  Suffix = ClusterId,
  Timestamp = integer_to_binary(os:system_time(second)),
  {ok, CWD} = file:get_cwd(),
  WD = filename:join([CWD, ?MODULE, Suffix, Timestamp]),
  ok = filelib:ensure_path(WD),
  {ok, State#{workdir => WD}}.

%% @private
cleanup_per_cluster(_ClusterId, _Conf, Success, #{workdir := WD}) ->
  DoClean = case os:getenv("FAMILIAR_WORKDIR_CLEANUP") of
              "false" -> false;
              "true"  -> true;
              _       -> Success
            end,
  case DoClean of
    true ->
      logger:notice("Cleaning up working directory ~s", [WD]),
      file:del_dir_r(WD);
    false ->
      logger:notice("Keeping working directory ~s", [WD]),
      ok
  end.

%% @private
init_per_site({_Cluster, Site}, _Conf, State = #{workdir := WDC}) ->
  WDS = familiar_lib:ensure_list(filename:join(WDC, Site)),
  ok = filelib:ensure_path(WDS),
  {ok, State#{workdir := WDS}}.

%% @private
init_per_node(Site, _Node, _Conf, State = #{workdir := WD}) ->
  case familiar_site:call(Site, file, set_cwd, [WD]) of
    ok ->
      {ok, State};
    Err ->
      Err
  end.

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================
