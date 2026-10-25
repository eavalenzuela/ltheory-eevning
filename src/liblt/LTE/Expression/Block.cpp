#include "../Expressions.h"

#include "LTE/AutoClass.h"
#include "LTE/Environment.h"
#include "LTE/Pool.h"
#include "LTE/Script.h"
#include "LTE/StringList.h"
#include "LTE/Vector.h"

#include "LTE/Debug.h"

#include <iostream>

namespace {
  bool IsComment(StringList const& statement) {
    return !statement->IsAtom()
        && statement->GetSize()
        && statement->Get(0)->IsAtom()
        && statement->Get(0)->GetValue() == "#";
  }

  /* Statements that legitimately compile to nothing: comments, declarations
     (which register themselves), and statements with a commented-out body. */
  bool IsIntentionallyEmpty(StringList const& statement) {
    if (statement->IsAtom() || !statement->GetSize())
      return false;
    if (IsComment(statement))
      return true;
    String const& head = statement->Get(0)->GetValue();
    if (head == "function" || head == "type")
      return true;
    for (size_t i = 1; i < statement->GetSize(); ++i)
      if (IsComment(statement->Get(i)))
        return true;
    return false;
  }

  AutoClassDerived(ExpressionBlock, ExpressionT,
    Vector<Expression>, expressions,
    Array<Type>, types,
    Array<Type>, locals)
    DERIVED_TYPE_EX(ExpressionBlock)
    POOLED_TYPE

    ExpressionBlock() {}

    ExpressionBlock(
        Vector<Expression> const& expressions,
        Vector<Type> const& locals) :
      expressions(expressions)
    {
      this->types.resize(expressions.size());
      this->locals.resize(locals.size());
      for (size_t i = 0; i < expressions.size(); ++i)
        this->types[i] = expressions[i]->GetType();
      for (size_t i = 0; i < locals.size(); ++i)
        this->locals[i] = locals[i];
    }

    String Emit(Vector<String>& context) const {
      context.push("{");
      Vector<String> localContext;
      String value;
      for (size_t i = 0; i < expressions.size(); ++i) {
        value = expressions[i]->Emit(localContext);
        if (value.size())
          localContext.push(value + ";");
      }

      for (size_t i = 0; i < localContext.size(); ++i)
        context.push("  " + localContext[i]);
      context.push("}");
      return value;
    }

    void Evaluate(void* returnValue, Environment& env) const {
      for (size_t i = 0; i < expressions.size(); ++i)
        if (i + 1 == expressions.size())
          expressions[i]->Evaluate(returnValue, env);
        else {
          if (types[i]->allocate) {
            void* lv = env.Allocate(types[i]);
            expressions[i]->Evaluate(lv, env);
            env.Free(types[i], lv);
          } else {
            expressions[i]->Evaluate(0, env);
          }
        }

      /* Destruct all locals that were constructed in this scope. */ {
        for (size_t i = 0; i < locals.size(); ++i) {
          Type const& local = locals[locals.size() - (i + 1)];
          if (local)
            env.Free(local, env.registers.back());
          env.registers.pop();
        }
      }
    }

    Type GetType() const {
      return expressions[expressions.size() - 1]->GetType();
    }

    bool IsConstant(CompileEnvironment& env) const {
      for (size_t i = 0; i < expressions.size(); ++i)
        if (!expressions[i]->IsConstant(env))
          return false;
      return true;
    }
  };
}

namespace LTE {
  Expression Expression_Block(
    Vector<Expression> const& expressions,
    Vector<Type> const& locals)
  {
    return new ExpressionBlock(expressions, locals);
  }

  Expression Expression_Block(
    StringList const& list,
    CompileEnvironment& env,
    uint startIndex)
  {
    Vector<Expression> expressions;
    Vector<String> localNames;

    for (size_t i = startIndex; i < list->GetSize(); ++i) {
      StringList const& statement = list->Get(i);

      /* Report each failing statement on its own, rather than only the first
         failure in the whole function. (Not during the detailed re-compile
         of an already-reported failure, which would repeat everything.) */
      bool report = !env.detail;
      bool hadErrors = env.hasErrors;
      int errors = env.errors;
      if (report)
        env.hasErrors = false;
      Expression e = Expression_Compile(statement, env, &localNames);
      env.hasErrors = hadErrors || env.hasErrors;

      if (e)
        expressions.push(e);
      else if (report && env.errors == errors && !IsIntentionallyEmpty(statement) && env.script)
        std::cout << "'" << env.script->name << "' line "
                  << StringList_GetLine(statement)
                  << " -- statement did not compile and was dropped: "
                  << statement->GetString() << std::endl;
    }

    Vector<Type> locals;
    for (size_t i = 0; i < localNames.size(); ++i) {
      String const& name = localNames[i];
      Variable const& var = env.Get(name);
      locals.push(var.reference ? nullptr : var.type);
      env.Free(name);
    }

    if (locals.size())
      return Expression_Block(expressions, locals);

    if (expressions.size() == 0)
      return nullptr;
    else if (expressions.size() == 1)
      return expressions[0];
    else
      return Expression_Block(expressions, locals);
  }
}
