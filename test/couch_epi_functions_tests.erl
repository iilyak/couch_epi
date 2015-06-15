-module(couch_epi_functions_tests).

-include_lib("couch/include/couch_eunit.hrl").

-define(MODULE1(Name), "
    -export([foo/2, bar/0, inc/1]).
    foo(A1, A2) ->
        {A1, A2}.

    bar() ->
        [].

    inc(A) ->
        A + 1.
").

-define(MODULE2(Name), "
    -export([baz/1, inc/1]).
    baz(A1) ->
        A1.

    inc(A) ->
        A + 1.
").

setup() ->
    setup([{interval, 100}]).

setup(Opts) ->
    ServiceId = my_service,
    Module = my_test_module,
    ok = generate_module(Module, ?MODULE1(Module)),
    {ok, Pid} = couch_epi_functions:start_link(
        test_app, {epi_key, ServiceId}, {modules, [Module]}, Opts),
    ok = couch_epi_functions:wait(Pid),
    {Pid, Module, ServiceId, couch_epi_functions_gen:get_handle(ServiceId)}.

teardown({Pid, Module, _, Handle}) ->
    code:purge(Module),
    %%code:purge(Handle), %% FIXME temporary hack
    couch_epi_functions:stop(Pid),
    catch meck:unload(compile),
    ok.

generate_module(Name, Body) ->
    Tokens = couch_epi_codegen:scan(Body),
    couch_epi_codegen:generate(Name, Tokens).

temp_atom() ->
    {A, B, C} = erlang:now(),
    list_to_atom(lists:flatten(io_lib:format("module~p~p~p", [A, B, C]))).


epi_functions_test_() ->
    {
        "functions reload tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun ensure_reload_if_changed/1,
                fun ensure_no_reload_when_no_change/1
            ]
        }
    }.

epi_functions_manual_reload_test_() ->
    {
        "functions manual reload tests",
        {
            foreach,
            fun() -> setup([{interval, 10000}]) end,
            fun teardown/1,
            [
                fun ensure_reload_if_manually_triggered/1
            ]
        }
    }.

ensure_reload_if_manually_triggered({Pid, Module, _ServiceId, _Handle}) ->
    ?_test(begin
        ok = generate_module(Module, ?MODULE2(Module)),
        ok = meck:new(compile, [passthrough, unstick]),
        ok = meck:expect(compile, forms, fun(_, _) -> {error, reload} end),
        Result = couch_epi_functions:reload(Pid),
        ?assertMatch({error,{badmatch,{error,reload}}}, Result)
    end).

ensure_reload_if_changed({_Pid, Module, ServiceId, Handle}) ->
    ?_test(begin
        ?assertMatch(
            [{1, 2}],
            couch_epi_functions_gen:apply(ServiceId, foo, [1, 2], [])),
        ok = generate_module(Module, ?MODULE2(Module)),
        timer:sleep(150),
        ?assertMatch(
            [3],
            couch_epi_functions_gen:apply(ServiceId, baz, [3], []))
    end).

ensure_no_reload_when_no_change({_Pid, Module, ServiceId, Handle}) ->
    ok = meck:new(compile, [passthrough, unstick]),
    ok = meck:expect(compile, forms, fun(_, _) ->
        {error, compile_should_not_be_called} end),
    ?_test(begin
        ?assertMatch(
            [{1, 2}],
            couch_epi_functions_gen:apply(ServiceId, foo, [1, 2], [])),
        timer:sleep(200),
        ?assertMatch(
            [],
            couch_epi_functions_gen:apply(ServiceId, baz, [3], []))
    end).
