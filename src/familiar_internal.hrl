%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-ifndef(FAMILIAR_INTERNAL_HRL).
-define(FAMILIAR_INTERNAL_HRL, true).

-record(fam_reg_cluster_sup, {cluster :: familiar:cluster_id()}).
-record(fam_reg_cluster_sites_sup, {cluster :: familiar:cluster_id()}).
-record(fam_reg_cluster_man, {cluster :: familiar:cluster_id()}).
-record(fam_reg_site, {cluster :: familiar:cluster_id(), site :: familiar:site()}).

-define(familiar_unknown_event, familiar_unknown_event).
-define(familiar_cluster_terminate, familiar_cluster_terminate).
-define(familiar_site_terminate, familiar_site_terminate).

-define(name(NAME), {n, l, NAME}).
-define(via(NAME), {via, gproc, ?name(NAME)}).

-ifndef(SNK_COLLECTOR).
  -define(SNK_COLLECTOR, true).
-endif.
-include_lib("snabbkaffe/include/trace.hrl").
-include("familiar.hrl").

-endif.
