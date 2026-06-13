%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-module(familiar_lib).

%% API:
-export([ is_normal_exit/1
        , ensure_list/1
        , get_ip_addr/3
        , merge_site_opts/2
        , merge_peer_opts/2
        , merge_site_opts/1
        ]).

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

-spec merge_site_opts(familiar:site_conf(), familiar:site_conf()) -> familiar:site_conf().
merge_site_opts(C1, C2) ->
  maps:merge_with(
    fun(fixtures, F1, F2) ->
        F1 ++ F2;
       (peer, P1, P2) ->
        merge_peer_opts(P1, P2);
       (_, _, V2) ->
        V2
    end,
    C1,
    C2).

-spec merge_site_opts([familiar:site_conf()]) -> familiar:site_conf().
merge_site_opts(L) ->
  lists:foldr(fun merge_site_opts/2, #{}, L).

-spec merge_peer_opts(peer:start_options(), peer:start_options()) -> peer:start_options().
merge_peer_opts(C1, C2) ->
  maps:merge_with(
    fun(args, A1, A2) ->
        A1 ++ A2;
       (_, _, V2) ->
        V2
    end,
    C1,
    C2).

%%================================================================================
%% Internal exports
%%================================================================================

%%================================================================================
%% Internal functions
%%================================================================================
