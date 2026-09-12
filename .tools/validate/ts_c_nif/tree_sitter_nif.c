// T2#13: minimal C NIF wrapping tree-sitter core + Go grammar (Rustler/cargo
// layer bypassed — cargo fs ops break under this PRoot; see RESULTS.md row 13).
#include <erl_nif.h>
#include <tree_sitter/api.h>

const TSLanguage *tree_sitter_go(void);

static uint64_t count_nodes(TSNode node) {
    uint64_t n = 1;
    uint32_t c = ts_node_child_count(node);
    for (uint32_t i = 0; i < c; i++) {
        n += count_nodes(ts_node_child(node, i));
    }
    return n;
}

static ERL_NIF_TERM parse_go_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary src;
    if (!enif_inspect_iolist_as_binary(env, argv[0], &src))
        return enif_make_badarg(env);

    TSParser *parser = ts_parser_new();
    if (!ts_parser_set_language(parser, tree_sitter_go())) {
        ts_parser_delete(parser);
        return enif_make_atom(env, "error");
    }
    TSTree *tree = ts_parser_parse_string(parser, NULL, (const char *)src.data, (uint32_t)src.size);
    ts_parser_delete(parser);
    if (!tree)
        return enif_make_atom(env, "error");

    TSNode root = ts_tree_root_node(tree);
    ERL_NIF_TERM out = enif_make_tuple3(env,
        enif_make_atom(env, "ok"),
        enif_make_uint64(env, count_nodes(root)),
        ts_node_has_error(root) ? enif_make_atom(env, "true") : enif_make_atom(env, "false"));
    ts_tree_delete(tree);
    return out;
}

static ErlNifFunc funcs[] = {{"parse_go", 1, parse_go_nif, 0}};
ERL_NIF_INIT(Elixir.TreeSitterCNif, funcs, NULL, NULL, NULL, NULL);
