#include "StringList.h"
#include "Location.h"
#include "Tokenizer.h"

#include "Debug.h"

#include <iostream>

namespace {
  String const kWhitespace = " \t\n\r";
  String const kTab = " ";
  String const kDelim = " ";
  const char kScopeOpen = '(';
  const char kScopeClose = ')';

  StringList StringList_ParseLine(String const& line) {
    Vector<StringList> elements;
    size_t i = 0;

    while (i < line.size()) {
      uint level = 0;
      String token;
      bool literal = false;
      bool escaped = false;

      /* Remove whitespace padding. */ {
        while (i < line.size() && kWhitespace.contains(line[i]))
          i++;
      }

      while (i < line.size()) {
        char c = line[i++];
        if (c == '\"' && !escaped)
          literal = !literal;

        if (escaped)
          escaped = false;

        if (literal) {
          if (c == '\\')
            escaped = true;
        } else {
          if (c == kScopeOpen)
            level++;
          if (c == kScopeClose) {
            level--;
            if (level == 0)
              break;
          }

          if (level == 0 && kDelim.contains(c))
            break;
        }

        token += c;
      }

      if (token.size()) {
        if (token.front() == kScopeOpen) {
          elements.push(StringList_ParseLine(token.substr(1)));
        } else
          elements.push(new StringListAtom(token));
      }
    }

    return new StringListList(elements);
  }

  void SetLine(StringList const& list, uint line) {
    if (list->line)
      return;
    list->line = line;
    for (size_t i = 0; i < list->GetSize() && !list->IsAtom(); ++i)
      SetLine(list->Get(i), line);
  }

  StringList StringList_ParseBlock(Tokenizer& tokenizer, uint indent) {
    Vector<StringList> elements;
    Vector<StringList> current;

    while (tokenizer.HasMore()) {
      current.clear();
      size_t cursor = tokenizer.GetCursor();
      uint lineNumber = tokenizer.GetLine();
      String line = tokenizer.ReadLine();
      if (line.containsOnly(kWhitespace))
        continue;

      uint thisIndent = Tokenizer::GetIndent(line, kTab);
      if (thisIndent < indent) {
        tokenizer.SetCursor(cursor);
        break;
      }

      /* Parse the current line. */ {
        StringList list = StringList_ParseLine(line);
        StringListList* l = (StringListList*)list.t;
        for (size_t i = 0; i < l->elements.size(); ++i) {
          SetLine(l->elements[i], lineNumber);
          current.push(l->elements[i]);
        }
      }

      /* Parse inner block. */ {
        size_t cursor = tokenizer.GetCursor();
        String nextLine = tokenizer.ReadLine();
        uint nextIndent = Tokenizer::GetIndent(nextLine, kTab);
        tokenizer.SetCursor(cursor);

        if (nextIndent > indent) {
          StringList list = StringList_ParseBlock(tokenizer, nextIndent);
          StringListList* l = (StringListList*)list.t;
          for (size_t i = 0; i < l->elements.size(); ++i)
            current.push(l->elements[i]);
        }
      }

      if (current.size() == 1 && current[0]->IsAtom())
        elements.push(current[0]);
      else {
        StringList statement = new StringListList(current);
        statement->line = lineNumber;
        elements.push(statement);
      }
    }
    return new StringListList(elements);
  }
}

StringList StringList_Create(String const& source) {
  Tokenizer tokenizer(source);
  return StringList_ParseBlock(tokenizer, 0);
}

uint StringList_GetLine(StringList const& list) {
  if (!list)
    return 0;
  if (list->line || list->IsAtom())
    return list->line;
  for (size_t i = 0; i < list->GetSize(); ++i) {
    uint line = StringList_GetLine(list->Get(i));
    if (line)
      return line;
  }
  return 0;
}

StringList StringList_Load(Location const& location) {
  return StringList_Create(location->ReadAscii());
}

void StringList_Print(StringList const& list) {
  if (list->IsAtom())
    std::cout << ((StringListAtom*)list.t)->value;
  else {
    StringListList* l = (StringListList*)list.t;
    std::cout << "(";
    for (size_t i = 0; i < l->elements.size(); ++i) {
      if (i) std::cout << " ";
      StringList_Print(l->elements[i]);
    }
    std::cout << ")";
  }
}
