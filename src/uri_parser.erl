%% This file is a copy of http_uri.erl from the R13B-1 Erlang/OTP
%% distribution with several modifications.

%% All modifications are (C) 2009 LShift Ltd.

%% ``The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved via the world wide web at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% The Initial Developer of the Original Code is Ericsson Utvecklings AB.
%% Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
%% AB. All Rights Reserved.''

%% See http://tools.ietf.org/html/rfc3986

-module(uri_parser).

-export([parse/2]).

%%%=========================================================================
%%%  API
%%%=========================================================================

%% Returns a key list of elements extracted from the URI. Note that
%% only 'scheme' is guaranteed to exist. Key-Value pairs from the
%% Defaults list will be used absence of a non-empty value extracted
%% from the URI. The values extracted are strings, except for 'port'
%% which is an integer, 'userinfo' which is a list of strings (split
%% on $:), and 'query' which is a list of strings where no $= char
%% found, or a {key,value} pair where a $= char is found (initial
%% split on $& and subsequent optional split on $=). Possible keys
%% are: 'scheme', 'userinfo', 'host', 'port', 'path', 'query',
%% 'fragment'.

parse(AbsURI, Defaults) ->
    case parse_scheme(AbsURI) of
	{error, Reason} ->
	    {error, Reason};
	{Scheme, Rest} ->
            case (catch parse_uri_rest(Rest)) of
                [_|_] = List ->
                    merge_keylists([{scheme, Scheme} | List], Defaults);
                _ ->
                    {error, {malformed_uri, AbsURI}}
            end
    end.

%%%========================================================================
%%% Internal functions
%%%========================================================================
parse_scheme(AbsURI) ->
    split_uri(AbsURI, ":", {error, no_scheme}, 1, 1).

parse_uri_rest("//" ++ URIPart) ->
    %% we have an authority
    {Authority, PathQueryFrag} =
	split_uri(URIPart, "/|\\?|#", {URIPart, ""}, 1, 0),
    AuthorityParts = parse_authority(Authority),
    parse_uri_rest(PathQueryFrag) ++ AuthorityParts;
parse_uri_rest(PathQueryFrag) ->
    %% no authority, just a path and maybe query
    {PathQuery, Frag} =
        split_uri(PathQueryFrag, "#", {PathQueryFrag, ""}, 1, 1),
    {Path, QueryString} = split_uri(PathQuery, "\\?", {PathQuery, ""}, 1, 1),
    QueryPropList = split_query(QueryString),
    [{path, Path}, {'query', QueryPropList}, {fragment, Frag}].

parse_authority(Authority) ->
    {UserInfo, HostPort} = split_uri(Authority, "@", {"", Authority}, 1, 1),
    UserInfoSplit = case inets_regexp:split(UserInfo, ":") of
                        {ok, [""]} -> [];
                        {ok, UIS } -> UIS
                    end,
    [{userinfo, UserInfoSplit} | parse_host_port(HostPort)].

parse_host_port("[" ++ HostPort) -> %ipv6
    {Host, ColonPort} = split_uri(HostPort, "\\]", {HostPort, ""}, 1, 1),
    [{host, Host} | case split_uri(ColonPort, ":", not_found, 0, 1) of
                        not_found -> [];
                        {_, Port} -> [{port, list_to_integer(Port)}]
                    end];

parse_host_port(HostPort) ->
    {Host, Port} = split_uri(HostPort, ":", {HostPort, not_found}, 1, 1),
    [{host, Host} | case Port of
                        not_found -> [];
                        _         -> [{port, list_to_integer(Port)}]
                    end].

split_query(Query) ->
    case inets_regexp:split(Query, "&") of
        {ok, [""]} ->
            [];
        {ok, QParams} ->
            lists:map(fun(Param) -> split_uri(Param, "=", Param, 1, 1) end,
                      QParams)
    end.

split_uri(UriPart, SplitChar, NoMatchResult, SkipLeft, SkipRight) ->
    case inets_regexp:first_match(UriPart, SplitChar) of
	{match, Match, _} ->
	    {string:substr(UriPart, 1, Match - SkipLeft),
	     string:substr(UriPart, Match + SkipRight, length(UriPart))};
	nomatch ->
	    NoMatchResult
    end.

merge_keylists(A, B) ->
    lists:ukeysort(1, lists:foldl(
                        fun ({Key, ""}, Acc) ->
                                case lists:keysearch(Key, 1, B) of
                                    {value, Pair} -> [Pair | Acc];
                                    false         -> [{Key, ""} | Acc]
                                end;
                            (Pair, Acc) ->
                                [Pair | Acc]
                        end, [], A) ++ B).
