%%--------------------------------------------------------------------
%% Copyright (c) 2025-2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

%% @doc Test fixture that configures and starts an OTP application.
%%
%% Configuration:
%%
%% <itemize>
%% <li>`app': OTP application</li>
%% <li>`env': Application environment variables to set,
%% represented as a key-value map.
%% Default is `#{}'.</li>
%% <li>`start': `true', start the application. `false', just load.
%% Default is `true'</li>
%% </itemize>
-module(familiar_app).

-behavior(familiar_fixture).

%% behavior callbacks:
-export([init_per_node/4, cleanup_per_node/4]).

-export_type([conf/0]).

-include_lib("kernel/include/logger.hrl").

%%================================================================================
%% Type declarations
%%================================================================================

-type conf() :: #{ app       := atom()
                 , env       => map() | fun((famliar:site(), node(), _State) -> map())
                 , start     => boolean()
                 , timeout   => timeout()
                 , prep_stop => fun((famliar:site(), node(), _State) -> _)
                 }.

%%================================================================================
%% behavior callbacks
%%================================================================================

%% @private
init_per_node(Site, Node, Conf, State) ->
  Defaults = #{ env   => #{}
              , start => true
              },
  #{ app   := App
   , env   := Env0
   , start := Start
   } = maps:merge(Defaults, Conf),
  Env = if is_map(Env0) ->
            Env0;
           is_function(Env0, 3) ->
            Env0(Site, Node, State)
        end,
  ok = familiar_site:call(
         Site,
         fun() ->
             case application:load(App) of
               ok                           -> ok;
               {error, {already_loaded, _}} -> ok
             end,
             maps:foreach(
               fun(K, V) ->
                   application:set_env(App, K, V)
               end,
               Env)
         end,
         timeout(Conf)),
  case Start of
    true ->
      {ok, Started} = familiar_site:call(Site, application, ensure_all_started, [App]);
    false ->
      Started = []
  end,
  {ok, State#{{?MODULE, App} => Started}}.

%% @private
cleanup_per_node(Site, Node, #{app := App} = Conf, State) ->
  #{{?MODULE, App} := Started} = State,
  case Conf of
    #{prep_stop := Fun} ->
      try
        Fun(Site, Node, State)
      catch
        EC:Err:Stack ->
          ?LOG_ERROR("prep_stop callback for application ~p failed: ~p:~p~nStack: ~p", [App, EC, Err, Stack])
      end;
    #{} ->
      ok
  end,
  familiar_site:call(
    Site,
    fun() ->
        lists:foreach(
          fun(App) ->
              ?LOG_DEBUG("Stopping ~p at ~p", [App, Node]),
              application:stop(App),
              ?LOG_DEBUG("Stopped ~p at ~p", [App, Node])
          end,
          %% fun application:stop/1,
          lists:reverse(Started))
    end,
    timeout(Conf)).

timeout(#{timeout := TO}) ->
  TO;
timeout(_) ->
  %% Make it larger than the default 5_000
  15_000.
