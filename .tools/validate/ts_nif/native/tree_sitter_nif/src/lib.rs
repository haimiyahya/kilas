use rustler::Atom;
use tree_sitter::{Language, Parser};

rustler::atoms! {
    ok,
    error,
}

#[rustler::nif]
fn parse_go(source: String) -> (Atom, u64, bool) {
    let language = Language::new(tree_sitter_go::LANGUAGE);
    let mut parser = Parser::new();
    if parser.set_language(&language).is_err() {
        return (error(), 0, true);
    }
    match parser.parse(&source, None) {
        Some(tree) => {
            let root = tree.root_node();
            let has_err = root.has_error();
            let n = count_nodes(&root);
            (ok(), n, has_err)
        }
        None => (error(), 0, true),
    }
}

fn count_nodes(node: &tree_sitter::Node) -> u64 {
    let mut cursor = node.walk();
    let mut n = 1u64;
    if cursor.goto_first_child() {
        loop {
            n += count_nodes(&cursor.node());
            if !cursor.goto_next_sibling() {
                break;
            }
        }
    }
    n
}

rustler::init!("Elixir.TreeSitterNif", [parse_go]);
