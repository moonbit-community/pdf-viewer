// Rabbita and the reader controller are compiled from cmd/viewer/*.mbt.
import "./viewer-host.mjs";
import {load_file} from "./_generated/viewer.js";
export {
  perform_search as performSearch,
  read_selection as readSelection,
  select_all_text as selectAllText,
  close_document as closeDocument,
  print_document as printDocument,
  runtime_diagnostics as runtimeDiagnostics,
} from "./_generated/viewer.js";
export const loadFile = (file, path = "") => load_file(file, path);
