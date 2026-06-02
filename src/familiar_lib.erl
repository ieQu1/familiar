%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(familiar_lib).

%% API:
-export([is_normal_exit/1, ensure_list/1, sync_stop_proc/3, get_ip_addr/3]).

-export_type([]).

%%================================================================================
%% Type declarations
%%================================================================================

%%================================================================================
%% API functions
%%================================================================================

-spec is_normal_exit(_) -> boolean().
is_normal_exit(Reason) ->
  case Reason of
    normal   -> true;
    shutdown -> true;
    _        -> false
  end.

%% @doc If input is a binary, convert it to a list.
%% Keep input list as is.
-spec ensure_list(binary() | string()) -> string().
ensure_list(L) when is_list(L) ->
  L;
ensure_list(Bin) when is_binary(Bin) ->
  binary_to_list(Bin).


%% @doc Send exit signal `Reason' to a process and wait for the shutdown.
-spec sync_stop_proc(pid() | atom(), _ExitReason, timeout()) -> ok | {error, timeout}.
sync_stop_proc(undefined, _, _) ->
  ok;
sync_stop_proc(Name, Reason, Timeout) when is_atom(Name) ->
  sync_stop_proc(whereis(Name), Reason, Timeout);
sync_stop_proc(Pid, Reason, Timeout) when is_pid(Pid) ->
  unlink(Pid),
  MRef = monitor(process, Pid),
  exit(Pid, Reason),
  logger:warning("Sys state ~p: ~p", [Pid, sys:get_state(Pid)]),
  receive
    {'DOWN', MRef, process, _, _} ->
      ok
  after Timeout ->
      {error, timeout}
  end.

-spec get_ip_addr(Addr, 0..32, non_neg_integer()) -> {ok, Addr} | {error, subnet_is_too_small}
          when Addr :: {byte(), byte(), byte(), byte()}.
get_ip_addr({NA, NB, NC, ND}, SubNet, SiteN) ->
  AddBits = 32 - SubNet,
  if
    SiteN < 1 bsl AddBits ->
      <<SA:8, SB:8, SC:8, SD:8>> = <<0:SubNet, SiteN:AddBits>>,
      {ok, {NA bor SA, NB bor SB, NC bor SC, ND bor SD}};
    true ->
      {error, subnet_is_too_small}
  end.

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================
