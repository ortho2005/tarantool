#!/usr/bin/env tarantool

local tap = require('tap')
local client = require('http.client')
local json = require('json')
local test = tap.test("curl")
local fiber = require('fiber')
local socketlib = require('socket')
local os = require('os')

local TARANTOOL_SRC_DIR = os.getenv("TARANTOOL_SRC_DIR") or "../.."
test:diag("TARANTOOL_SRC_DIR=%s", TARANTOOL_SRC_DIR)

local function merge(...)
    local res = {}
    for i = 1, select('#', ...) do
        local t = select(i, ...)
        for k, v in pairs(t) do
            res[k] = v
        end
    end
    return res
end

local function start_server(testcase, sock_family, sock_addr)
    testcase:diag("starting HTTP server on %s...", sock_addr)
    local arg, url, opts
    if sock_family == 'AF_INET' then
        arg = string.format("--inet %s", sock_addr)
        url = string.format("http://%s/", sock_addr)
        opts = {}
    elseif sock_family == 'AF_UNIX' then
        arg = string.format("--unix %s", sock_addr)
        url = "http://localhost/"
        opts = {unix_socket = sock_addr}
    else
        error(string.format('invalid socket family: %s', sock_family))
    end
    local cmd = string.format("%s/test/app-tap/httpd.py %s",
                              TARANTOOL_SRC_DIR, arg)
    local server = io.popen(cmd)
    testcase:is(server:read("*l"), "heartbeat", "server started")
    testcase:diag("trying to connect to %s", url)
    local r
    for _=1,10 do
        r = client.get(url, merge(opts, {timeout = 0.01}))
        if r.status == 200 then
            break
        end
        fiber.sleep(0.01)
    end
    testcase:is(r.status, 200, "connection is ok")
    if r.status ~= 200 then
        os.exit(1)
    end
    return server, url, opts
end

local function stop_server(testcase, server)
    testcase:diag("stopping HTTP server")
    server:close()
end

local function test_http_client(testcase, url, opts)
    testcase:plan(11)

    -- gh-4136: confusing httpc usage error message
    local ok, err = pcall(client.request, client)
    local usage_err = "request(method, url[, body, [options]])"
    testcase:is_deeply({ok, err:split(': ')[2]}, {false, usage_err},
                   "test httpc usage error")

    testcase:isnil(rawget(_G, 'http'), "global namespace is not polluted");
    testcase:isnil(rawget(_G, 'http.client'), "global namespace is not polluted");
    local r = client.get(url, opts)
    testcase:is(r.status, 200, 'simple 200')
    testcase:is(r.reason, 'Ok', '200 - Ok')
    testcase:is(r.proto[1], 1, 'proto major http 1.1')
    testcase:is(r.proto[2], 1, 'proto major http 1.1')
    testcase:ok(r.body:match("hello") ~= nil, "body")
    testcase:ok(tonumber(r.headers["content-length"]) > 0,
        "content-length > 0")
    testcase:is(client.get("http://localhost:1/").status, 595, 'cannot connect')

    r = client.request('GET', url, nil, opts)
    testcase:is(r.status, 200, 'request')

    -- XXX: enable after resolving of gh-4180: httpc: redirects
    -- are broken with libcurl-7.30 and older
    --[[
    -- gh-4119: specify whether to follow 'Location' header
    test:test('gh-4119: follow location', function(test)
        test:plan(7)
        local endpoint = 'redirect'

        -- Verify that the default behaviour is to follow location.
        local r = client.request('GET', url .. endpoint, nil, opts)
        test:is(r.status, 200, 'default: status')
        test:is(r.body, 'hello world', 'default: body')

        -- Verify {follow_location = true} behaviour.
        local r = client.request('GET', url .. endpoint, nil, merge(opts, {
                                 follow_location = true}))
        test:is(r.status, 200, 'follow location: status')
        test:is(r.body, 'hello world', 'follow location: body')

        -- Verify {follow_location = false} behaviour.
        local r = client.request('GET', url .. endpoint, nil, merge(opts, {
                                 follow_location = false}))
        test:is(r.status, 302, 'do not follow location: status')
        test:is(r.body, 'redirecting', 'do not follow location: body')
        test:is(r.headers['location'], '/', 'do not follow location: header')
    end)
    ]]--
end

--
-- gh-3955: Check that httpc module doesn't redefine http headers
--          set explicitly by the caller.
--
local function test_http_client_headers_redefine(testcase, url, opts)
    testcase:plan(9)
    opts = table.deepcopy(opts)
    -- Test defaults
    opts.headers = {['Connection'] = nil, ['Accept'] = nil}
    local r = client.post(url, nil, opts)
    testcase:is(r.status, 200, 'simple 200')
    testcase:is(r.headers['connection'], 'close', 'Default Connection header')
    testcase:is(r.headers['accept'], '*/*', 'Default Accept header for POST request')
    -- Test that in case of conflicting headers, user variant is
    -- prefered
    opts.headers={['Connection'] = 'close'}
    opts.keepalive_idle = 2
    opts.keepalive_interval = 1
    r = client.get(url, opts)
    testcase:is(r.status, 200, 'simple 200')
    testcase:is(r.headers['connection'], 'close', 'Redefined Connection header')
    testcase:is(r.headers['keep_alive'], 'timeout=2',
            'Automatically set Keep-Alive header')
    -- Test that user-defined Connection and Acept headers
    -- are used
    opts.headers={['Connection'] = 'Keep-Alive', ['Accept'] = 'text/html'}
    r = client.get(url, opts)
    testcase:is(r.status, 200, 'simple 200')
    testcase:is(r.headers['accept'], 'text/html', 'Redefined Accept header')
    testcase:is(r.headers['connection'], 'Keep-Alive', 'Redefined Connection header')
end

local function test_cancel_and_errinj(testcase, url, opts)
    testcase:plan(3)
    local ch = fiber.channel(1)
    local http = client:new()
    local func  = function(fopts)
        ch:put(http:get(url, fopts))
    end
    local f = fiber.create(func, opts)
    f:cancel()
    local r = ch:get()
    testcase:ok(r.status == 408 and string.find(r.reason, "Timeout"),
                    "After cancel fiber timeout is returned")
    r = http:get(url, merge(opts, {timeout = 0.0001}))
    testcase:ok(r.status == 408 and string.find(r.reason, "Timeout"),
                                                       "Timeout check")
    local errinj = box.error.injection
    errinj.set('ERRINJ_HTTP_RESPONSE_ADD_WAIT', true)
    local topts = merge(opts, {timeout = 1200})
    fiber.create(func, topts)
    r = ch:get()
    testcase:is(r.status, 200, "No hangs in errinj")
    errinj.set('ERRINJ_HTTP_RESPONSE_ADD_WAIT', false)
end

local function test_post_and_get(testcase, url, opts)
    testcase:plan(21)

    local http = client.new()
    testcase:ok(http ~= nil, "client is created")

    local headers = { header1 = "1", header2 = "2" }
    local my_body = { key = "value" }
    local json_body = json.encode(my_body)
    local responses = {}
    headers['Content-Type'] = 'application/json'
    local fibers = 7
    local ch = fiber.channel(fibers)
    opts = merge(opts, {headers = headers})
    fiber.create(function()
        responses.good_get = http:get(url, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.get2 = http:get(url .. "abc", opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.good_post = http:post(url, json_body, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.empty_post = http:post(url, nil, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.good_put = http:put(url, json_body, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.bad_get = http:get(url .. 'this/page/not/exists', opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.absent_get = http:get(url .. 'absent', opts)
        ch:put(1)
    end)
    for _=1,fibers do
        ch:get()
    end
    local r = responses.good_get
    testcase:is(r.status, 200, "GET: default http code page exists")
    testcase:is(r.body, "hello world", "GET: default right body")

    r = responses.get2
    testcase:is(r.status, 200, "GET: http code page exists")
    testcase:is(r.body, "abc", "GET: right body")

    r = responses.absent_get
    testcase:is(r.status, 500, "GET: absent method http code page exists")
    testcase:is(r.reason, 'Unknown', '500 - Unknown')
    testcase:is(r.body, "No such method", "GET: absent method right body")

    r = responses.empty_post
    testcase:is(r.status, 200, "POST: good status")
    testcase:ok(r.headers['header1'] == headers.header1 and
        r.headers['header2'] == headers.header2, "POST: good headers")
    testcase:isnil(r.body, "POST: empty body")

    r = responses.good_post
    testcase:is(r.status, 200, "POST: good status")
    testcase:ok(r.headers['header1'] == headers.header1 and
        r.headers['header2'] == headers.header2, "POST: good headers")
    testcase:is(r.body, json_body, "POST: body")

    r = responses.good_put
    testcase:is(r.status, 200, "PUT: good status")
    testcase:ok(r.headers['header'] == headers.header and
        r.headers['header2'] == headers.header2, "PUT: good headers")

    r = responses.bad_get
    testcase:is(r.status, 404, "GET: http page not exists")
    testcase:is(r.reason, 'Unknown', '404 - Unknown')
    testcase:isnt(r.body:len(), 0, "GET: not empty body page not exists")
    testcase:ok(string.find(r.body, "Not Found"),
                "GET: right body page not exists")

    local st = http:stat()
    testcase:ok(st.sockets_added == st.sockets_deleted and
        st.active_requests == 0,
        "stats checking")
end

local function test_errors(testcase)
    testcase:plan(2)
    local http = client:new()
    local status, err = pcall(http.get, http, "htp://mail.ru")
    testcase:ok(not status and string.find(json.encode(err),
                        "Unsupported protocol"),
                        "GET: exception on bad protocol")
    status, err = pcall(http.post, http, "htp://mail.ru", "")
    testcase:ok(not status and string.find(json.encode(err),
                        "Unsupported protocol"),
                        "POST: exception on bad protocol")
end

-- gh-3679 Check that opts.headers values can be strings only.
-- gh-4281 Check that opts.headers can be a table and opts.headers
-- keys can be strings only.
local function test_request_headers(testcase, url, opts)
    local exp_err_bad_opts_headers = 'opts.headers should be a table'
    local exp_err_bad_key = 'opts.headers keys should be strings'
    local exp_err_bad_value = 'opts.headers values should be strings'
    local cases = {
        -- Verify opts.headers type checks.
        {
            'string opts.headers',
            opts = {headers = 'aaa'},
            exp_err = exp_err_bad_opts_headers,
        },
        {
            'number opts.headers',
            opts = {headers = 1},
            exp_err = exp_err_bad_opts_headers,
        },
        {
            'cdata (box.NULL) opts.headers',
            opts = {headers = box.NULL},
            exp_err = exp_err_bad_opts_headers,
        },
        -- Verify a header key type checks.
        {
            'number header key',
            opts = {headers = {[1] = 'aaa'}},
            exp_err = exp_err_bad_key,
        },
        {
            'boolean header key',
            opts = {headers = {[true] = 'aaa'}},
            exp_err = exp_err_bad_key,
        },
        {
            'table header key',
            opts = {headers = {[{}] = 'aaa'}},
            exp_err = exp_err_bad_key,
        },
        {
            'cdata header key (box.NULL)',
            opts = {headers = {[box.NULL] = 'aaa'}},
            exp_err = exp_err_bad_key,
        },
        -- Verify a header value type checks.
        {
            'string header key & value',
            opts = {headers = {aaa = 'aaa'}},
            exp_err = nil,
        },
        {
            'boolean header value',
            opts = {headers = {aaa = true}},
            exp_err = exp_err_bad_value,
        },
        {
            'number header value',
            opts = {headers = {aaa = 10}},
            exp_err = exp_err_bad_value,
        },
        {
            'cdata header value (box.NULL)',
            opts = {headers = {aaa = box.NULL}},
            exp_err = exp_err_bad_value,
        },
        {
            'cdata<uint64_t> header value',
            opts = {headers = {aaa = 10ULL}},
            exp_err = exp_err_bad_value,
        },
        {
            'table header value',
            opts = {headers = {aaa = {}}},
            exp_err = exp_err_bad_value,
        },
    }
    testcase:plan(#cases)

    local http = client:new()

    for _, case in ipairs(cases) do
        opts = merge(table.copy(opts), case.opts)
        local ok, err = pcall(http.get, http, url, opts)
        if case.postrequest_check ~= nil then
            case.postrequest_check(opts)
        end
        if case.exp_err == nil then
            -- expect success
            testcase:ok(ok, case[1])
        else
            -- expect fail
            assert(type(err) == 'string')
            err = err:gsub('^builtin/[a-z._]+.lua:[0-9]+: ', '')
            testcase:is_deeply({ok, err}, {false, case.exp_err}, case[1])
        end
    end
end

local function test_headers(testcase, url, opts)
    testcase:plan(21)
    local http = client:new()
    local r = http:get(url .. 'headers', opts)
    testcase:is(type(r.headers["set-cookie"]), 'string', "set-cookie check")
    testcase:ok(r.headers["set-cookie"]:match("likes=cheese"), "set-cookie check")
    testcase:ok(r.headers["set-cookie"]:match("age = 17"), "set-cookie check")
    testcase:is(r.headers["content-type"], "application/json", "content-type check")
    testcase:is(r.headers["my_header"], "value1,value2", "other header check")
    testcase:isnil(r.headers["11200ok"], "http status line not included in headers")
    testcase:is(r.cookies["likes"][1], "cheese", "cookie value check")
    testcase:ok(r.cookies["likes"][2][1]:match("Expires"), "cookie option check")
    testcase:ok(r.cookies["likes"][2][3]:match("HttpOnly"), "cookie option check")
    testcase:is(r.cookies["age"][1], "17", "cookie value check")
    testcase:is(#r.cookies["age"][2], 1, "cookie option check")
    testcase:is(r.cookies["age"][2][1], "Secure", "cookie option check")
    testcase:ok(r.cookies["good_name"] ~= nil , "cookie name check")
    testcase:ok(r.cookies["bad@name"] == nil , "cookie name check")
    testcase:ok(r.cookies["badname"] == nil , "cookie name check")
    testcase:ok(r.cookies["badcookie"] == nil , "cookie name check")
    testcase:isnil(r.headers["very_very_very_long_headers_name1"], "no long header name")
    testcase:is(r.headers["very_very_very_long_headers_name"], "true", "truncated name")
    opts["max_header_name_length"] = 64
    r = http:get(url .. 'headers', opts)
    testcase:is(r.headers["very_very_very_long_headers_name1"], "true", "truncated max_header_name_length")
    opts["max_header_name_length"] = nil

    -- Send large headers.
    local MAX_HEADER_NAME = 8192
    local hname = 'largeheader'

    -- "${hname}: ${hvalue}" is 8192 bytes length
    local hvalue = string.rep('x', MAX_HEADER_NAME - hname:len() - 2)
    local headers = {[hname] = hvalue}
    r = http:post(url, nil, merge(opts, {headers = headers}))
    testcase:is(r.headers[hname], hvalue, '8192 bytes header: success')

    -- "${hname}: ${hvalue}" is 8193 bytes length
    local exp_err = 'header is too large'
    hvalue = string.rep('x', MAX_HEADER_NAME - hname:len() - 1)
    headers = {[hname] = hvalue}
    local ok, err = pcall(http.post, http, url, nil,
                          merge(opts, {headers = headers}))
    testcase:is_deeply({ok, tostring(err)}, {false, exp_err},
                   '8193 KiB header: error')
end

local function test_special_methods(testcase, url, opts)
    testcase:plan(14)
    local http = client.new()
    local responses = {}
    local fibers = 7
    local ch = fiber.channel(fibers)
    fiber.create(function()
        responses.patch_data = http:patch(url, "{\"key\":\"val\"}", opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.delete_data = http:delete(url, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.options_data = http:options(url, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.head_data = http:head(url, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.trace_data = http:trace(url, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.connect_data = http:connect(url, opts)
        ch:put(1)
    end)
    fiber.create(function()
        responses.custom_data = http:request("CUSTOM", url, nil, opts)
        ch:put(1)
    end)
    for _ = 1, fibers do
        ch:get()
    end

    testcase:is(responses.patch_data.status, 200, "HTTP:PATCH request")
    testcase:ok(json.decode(responses.patch_data.body).key == "val",
        "HTTP:PATCH request content")
    testcase:is(responses.delete_data.status, 200, "HTTP:DELETE request")
    testcase:ok(responses.delete_data.headers.method == "DELETE",
        "HTTP:DELETE request content")
    testcase:is(responses.options_data.status, 200, "HTTP:OPTIONS request")
    testcase:ok(responses.options_data.headers.method == "OPTIONS",
        "HTTP:OPTIONS request content")
    testcase:is(responses.head_data.status, 200, "HTTP:HEAD request code")
    testcase:ok(responses.head_data.headers.method == "HEAD",
        "HTTP:HEAD request content")
    testcase:is(responses.connect_data.status, 200, "HTTP:CONNECT request")
    testcase:ok(responses.connect_data.headers.method == "CONNECT",
        "HTTP:OPTIONS request content")
    testcase:is(responses.trace_data.status, 200, "HTTP:TRACE request")
    testcase:ok(responses.trace_data.headers.method == "TRACE",
        "HTTP:TRACE request content")
    testcase:is(responses.custom_data.status, 400, "HTTP:CUSTOM request")
    testcase:ok(responses.custom_data.headers.method == "CUSTOM",
        "HTTP:CUSTOM request content")
end

local function test_concurrent(testcase, url, opts)
    testcase:plan(3)
    local num_test = 10
    local num_load = 10
    local curls   = { }
    local headers = { }

    -- Init [[
    for i = 1, num_test do
        headers["My-header" .. i] = "my-value"
    end

    for _ = 1, num_test do
        table.insert(curls, {
            url = url,
            http = client.new(),
            body = json.encode({stat = {"ok"},
            info = {"ok"} }),
            headers = headers,
            connect_timeout = 5,
            timeout = 5
        })
    end
    -- ]]

    local ch = fiber.channel(num_test * 2 * num_load)
    -- Start test
    -- Creating concurrent clients
    for i=1,num_test do
        local obj = curls[i]
        for _=1,num_load do
            fiber.create(function()
                local r = obj.http:post(obj.url, obj.body, merge(opts, {
                    headers = obj.headers,
                    keepalive_idle = 30,
                    keepalive_interval = 60,
                    connect_timeout = obj.connect_timeout,
                    timeout = obj.timeout,
                }))
                ch:put(r.status)
            end)
            fiber.create(function()
                local r = obj.http:get(obj.url, merge(opts, {
                    headers = obj.headers,
                    keepalive_idle = 30,
                    keepalive_interval = 60,
                    connect_timeout = obj.connect_timeout,
                    timeout = obj.timeout,
                }))
                ch:put(r.status)
            end)
        end
    end
    local ok_sockets_added = true
    local ok_active = true
    local ok_req = true

    -- Join test
    local rest = num_test
    while true do
        for i = 1, num_load do
            local obj = curls[i]
            -- checking that stats in concurrent are ok
            if obj.http ~= nil and obj.http:stat().active_requests == 0 then
                local st = obj.http:stat()
                if st.sockets_added ~= st.sockets_deleted then
                    ok_sockets_added = false
                    rest = 0
                end
                if st.active_requests ~= 0 then
                    ok_active = false
                    rest = 0
                end
                -- waiting requests to finish before kill the client
                local r = ch:get()
                if r ~= 200 then
                    ok_req = false
                end
                r = ch:get()
                if r ~= 200 then
                    print(r)
                end
            end
            curls[i].http = nil
        end
        rest = rest - 1
        if rest <= 0 then
            break
        end
    end
    testcase:is(ok_req, true, "All requests are ok")
    testcase:ok(ok_sockets_added, "free sockets")
    testcase:ok(ok_active, "no active requests")
end

local function run_tests(testcase, sock_family, sock_addr)
    testcase:plan(11)
    local server, url, opts = start_server(testcase, sock_family, sock_addr)
    testcase:test("http.client", test_http_client, url, opts)
    testcase:test("http.client headers redefine", test_http_client_headers_redefine,
              url, opts)
    testcase:test("cancel and errinj", test_cancel_and_errinj, url .. 'long_query', opts)
    testcase:test("basic http post/get", test_post_and_get, url, opts)
    testcase:test("errors", test_errors)
    testcase:test("request_headers", test_request_headers, url, opts)
    testcase:test("headers", test_headers, url, opts)
    testcase:test("special methods", test_special_methods, url, opts)
    if sock_family == 'AF_UNIX' and jit.os ~= "Linux" then
        --
        -- BSD-based operating systems (including OS X) will fail
        -- connect() to a Unix domain socket with ECONNREFUSED
        -- if the queue of pending connections is full. Hence the
        -- "concurrent" test, which opens a lot of connections
        -- simultaneously, cannot run on those platforms. Linux,
        -- however, is fine - instead of returning ECONNEREFUSED
        -- it will suspend connect() until backlog is processed.
        --
        testcase:skip("concurrent")
    else
        testcase:test("concurrent", test_concurrent, url, opts)
    end
    stop_server(testcase, server)
end

test:plan(2)

test:test("http over AF_INET", function(testcase)
    local s = socketlib('AF_INET', 'SOCK_STREAM', 0)
    s:bind('127.0.0.1', 0)
    local host = s:name().host
    local port = s:name().port
    s:close()
    run_tests(testcase, 'AF_INET', string.format("%s:%d", host, port))
end)

test:test("http over AF_UNIX", function(testcase)
    local path = os.tmpname()
    os.remove(path)
    local status = pcall(client.get, 'http://localhost/', {unix_socket = path})
    if not status then
        -- Unix domain sockets are not supported, skip the test.
        return
    end
    run_tests(testcase, 'AF_UNIX', path)
    os.remove(path)
end)

os.exit(test:check() == true and 0 or -1)
