%%--------------------------------------------------------------------
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------
-ifndef(FAMILIAR_HRL).
-define(FAMILIAR_HRL, true).

-define(familiar_abnormal_exit, familiar_abnormal_exit).

-ifndef(ON).
-define(ON(SITE, BODY), familiar_site:call(SITE, fun() -> BODY end)).
-endif.

-endif.
