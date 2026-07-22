%%--------------------------------------------------------------------
%% copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @doc Test fixture that configures logger.
%%
%% It must run after `familiar_workdir'
-module(familiar_logger).

-behavior(familiar_fixture).

%% behavior callbacks:
-export([init_per_cluster/3, init_per_node/4, cleanup_per_node/5]).

-export_type([conf/0]).

-include("familiar.hrl").

%%================================================================================
%% Type declarations
%%================================================================================

-type conf() :: #{ level          => _
                 , primary_config => logger:primary_config()
                 , handler_config => _
                 }.

%%================================================================================
%% behavior callbacks
%%================================================================================

%% @private
init_per_cluster(_Cluster, Conf, State = #{workdir := _}) ->
  LogLevel = level(Conf),
  {ok, State#{log_level => LogLevel}};
init_per_cluster(_Cluster, _Conf, _State) ->
  error(logger_needs_work_dir).

%% @private
init_per_node(Site, _Node, Conf, State) ->
  #{workdir := _WorkDir, log_level := Level} = State,
  LogFile = "erlang.log",
  Handler = ?MODULE,
  ?ON(Site,
      begin
        ok = logger:set_primary_config(primary_config(Level, Conf)),
        ok = logger:add_handler(Handler, logger_std_h, handler_config(LogFile, Conf))
      end),
  {ok, State#{log_file => LogFile, log_handler => Handler}}.

%% @private
cleanup_per_node(Site, _Node, _Conf, #{log_handler := Handler}, _IsKill) ->
  ?ON(Site,
      begin
        ok = logger_std_h:filesync(Handler)
      end).

primary_config(Level, Conf) ->
  Default =
    #{ level          => Level
     , filter_default => log
     , filters        => default_filters(Level)
     },
  case Conf of
    #{primary_config := Custom} ->
      maps:merge(Default, Custom);
    #{} ->
      Default
  end.

handler_config(LogFile, Conf) ->
  Default =
    #{ filter_default => log
     , level => all
     , config => #{ type => file
                  , file => LogFile
                  , filesync_repeat_interval => 100
                  }
     , formatter => {logger_formatter, #{ single_line => false
                                        , legacy_header => true
                                        }}
     },
  case Conf of
    #{handler_config := Custom} ->
      maps:merge(Default, Custom);
    #{} ->
      Default
  end.

default_filters(_Level) ->
  ProgressArgs = case os:getenv("FAMILIAR_LOG_PROGRESS") of
                   false -> stop;
                   _     -> log
                 end,

  [ {progress, {fun logger_filters:progress/2, ProgressArgs}}
  ].

level(Conf) ->
  case os:getenv("FAMILIAR_LOG_LEVEL", "info") of
    "debug"    -> debug;
    "info"     -> info;
    "notice"   -> notice;
    "warning"  -> warning;
    "error"    -> error;
    "critical" -> critical;
    "alert"    -> alert;
    _          -> maps:get(level, Conf, debug)
  end.
