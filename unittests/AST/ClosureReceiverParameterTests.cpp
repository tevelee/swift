//===--- ClosureReceiverParameterTests.cpp
//---------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "TestContext.h"
#include "swift/AST/Expr.h"
#include "swift/AST/ParameterList.h"
#include "gtest/gtest.h"

using namespace swift;
using namespace swift::unittest;

namespace {
ClosureExpr *makeClosure(ASTContext &ctx) {
  return new (ctx)
      ClosureExpr(DeclAttributes(), SourceRange(), /*capturedSelfDecl=*/nullptr,
                  /*params=*/nullptr, SourceLoc(), SourceLoc(),
                  /*thrownType=*/nullptr, SourceLoc(), SourceLoc(),
                  /*explicitResultType=*/nullptr, ctx.getStdlibModule());
}

ParamDecl *makeParameter(ClosureExpr *closure, Identifier name) {
  auto &ctx = closure->getASTContext();
  auto *parameter = new (ctx) ParamDecl(
      SourceLoc(), SourceLoc(), Identifier(), SourceLoc(), name, closure);
  parameter->setSpecifier(ParamSpecifier::Default);
  parameter->setInterfaceType(ctx.TheEmptyTupleType);
  return parameter;
}
} // namespace

TEST(ClosureReceiverParameter, FollowsClonedParameterList) {
  TestContext C;
  C.LangOpts.enableFeature(Feature::ClosureReceiverParameters);
  auto &ctx = C.Ctx;
  auto *closure = makeClosure(ctx);
  auto *before = makeParameter(closure, ctx.getIdentifier("before"));
  auto *receiver = makeParameter(closure, ctx.Id_self);
  closure->setParameterList(ParameterList::create(ctx, {before, receiver}));
  closure->setReceiverParameter(1);

  EXPECT_EQ(closure->getReceiverParameter(), receiver);
  EXPECT_TRUE(receiver->isClosureReceiverParameter());
  EXPECT_FALSE(receiver->isSelfParameter());
  EXPECT_FALSE(before->isClosureReceiverParameter());

  auto *clonedParameters = ParameterList::clone(ctx, closure->getParameters());
  auto *clonedReceiver = clonedParameters->get(1);
  closure->setParameterList(clonedParameters);

  EXPECT_EQ(closure->getReceiverParameter(), clonedReceiver);
  EXPECT_TRUE(clonedReceiver->isClosureReceiverParameter());
  EXPECT_FALSE(clonedReceiver->isSelfParameter());
  EXPECT_FALSE(receiver->isClosureReceiverParameter());
}

TEST(ClosureReceiverParameter, RequiresExplicitSelectionAndFeature) {
  TestContext C;
  auto &ctx = C.Ctx;
  auto *closure = makeClosure(ctx);
  auto *parameter = makeParameter(closure, ctx.Id_self);
  closure->setParameterList(ParameterList::create(ctx, {parameter}));

  closure->setReceiverParameter(0);
  EXPECT_EQ(closure->getReceiverParameter(), nullptr);
  EXPECT_FALSE(parameter->isClosureReceiverParameter());

  C.LangOpts.enableFeature(Feature::ClosureReceiverParameters);
  EXPECT_EQ(closure->getReceiverParameter(), nullptr);
  closure->setReceiverParameter(0);
  EXPECT_EQ(closure->getReceiverParameter(), parameter);
}
