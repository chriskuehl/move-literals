#!/usr/bin/env lua
-- vim: set tabstop=2 shiftwidth=2 expandtab cc=80:

-- Writes a transformation of a C source code file where all the string
-- literals have been moved to the beginning of the code, to stdout.
--
-- Requires lua (probably 5.2 or 5.3) and LPeg

lpeg = require"lpeg"

-- minimum length of string to be replaced
MINLEN = 4

-- symbol prefix for #define statements
SYMPREFIX = "STRSYM_"

function build_parser(syms)
  local P  = lpeg.P    -- literal pattern, matches a string
  local V  = lpeg.V    -- non-terminal, references a grammar rule
  local S  = lpeg.S    -- set, matches a set of characters
  local B  = lpeg.B    -- look-behind
  local C  = lpeg.C    -- capture, captures the match of its argument pattern
  local Cs = lpeg.Cs   -- capture substitution
  local Ct = lpeg.Ct   -- table capture, creates a table of its captures

  local function cap(str)
    if #str >= MINLEN then
      local label = SYMPREFIX..str:gsub("%W", "_"):upper()
      syms[label] = str
      return label
    else
      return "\""..str.."\""
    end
  end

  -- NB: currently, this grammar captures all tokens to a table. Tokens
  -- that are not comments, preprocessor macros or string literals are one
  -- byte. That probably means a lot of overhead and can most likely be
  -- improved on. It shouldn't matter that much though, unless your source
  -- files are huge.
  return P{
    "code";
    lit_esc  = P"\\"*P(1),   -- matches a \ followed by any byte
    lit_cont = 1-S"\n\r\"",  -- matches any byte not in the given set

    -- matches lit_esc, or if lit_esc doesn't match, matches lit_count,
    -- zero or more times and substitutes the match for the value returned by
    -- the cap function
    in_lit   = Cs(((V"lit_esc" + V"lit_cont")^0)/cap),

    -- matches " followed by the in_lit rule, followed by "
    literal  = P"\"" * V"in_lit" * P"\"",

    -- matches (\r at most 1 time followed by \n), or end of data
    newline  = (P"\r"^-1 * P"\n") + -1,

    -- matches the newline rule if it is preceded by something that's not
    -- a backslash
    endmacro = -B"\\" * V"newline",

    -- matches the literal patterns for macro directives
    macrodir = P"#define" + P"#error" + P"#warning" + P"#undef" + P"#ifdef" +
               P"#ifndef" + P"#if" + P"#else" + P"#elif" + P"#endif" +
               P"#pragma",

    -- matches the rule for macro directives followed by zero or more
    -- bytes where the endmacro rule does not match, followed by the endmacro
    -- rule
    macro    = V"macrodir"* (1-V"endmacro")^0 * V"endmacro",

    -- matches C single line comments; // followed by zero or more bytes where
    -- the newline rule does not match, followed by the newline rule
    scomment = P"//" * (1-V"newline")^0 * V"newline",

    -- matches C multi line comments; see the scomment rule
    mcomment = P"/*" * (1-P"*/")^0 * P"*/",

    code     = Ct( -- takes all captures from the pattern below and puts
                   -- them in a table
                  (
                    -- matches the mcomment rule, or the scomment rule, or
                    -- the macro rule and takes the result
                    C(V"mcomment" + V"scomment" + V"macro")

                    -- or matches the literal rule, where the capture is
                    -- produced in the in_lit rule
                    + V"literal"

                    -- or matches and captures any byte
                    + C(P(1))

                  -- zero or more times
                  )^0
                 ),
  }
end

function load_data(file)
  f, err = io.open(file, "rb")
  if err ~= nil then
    error(err)
  end
  data = f:read("*a")
  f:close()
  if data == nil then
    error("error reading data")
  end
  return data
end

if arg[1] == nil then
  error("usage: move-literals.lua <in-file>")
end

local data = load_data(arg[1])
local syms = {}
local p = build_parser(syms)
res = p:match(data)
for label, str in pairs(syms) do
  io.write(string.format("#define %s \\\n   \"%s\"\n", label, str))
end
io.write(table.concat(res))
