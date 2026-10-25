#include "../Tasks.h"

#include "Component/Interior.h"
#include "Component/MotionControl.h"
#include "Component/Navigable.h"

#include "Game/Conditions.h"
#include "Game/Items.h"
#include "Game/Messages.h"
#include "Game/Player.h"

#include "LTE/Pool.h"
#include "LTE/SDFs.h"
#include "LTE/StackFrame.h"

#include "LTE/Debug.h"

/* Warp: legs longer than kWarpMinDistance are covered EVE-style. The ship
   aligns toward the destination under normal thrust, then moves along the
   leg on a smooth ease-in/out curve and drops out kWarpExitDistance from
   the destination's surface, from where normal flight takes over. */
const Distance kWarpMinDistance = 10000;
const Distance kWarpExitDistance = 2000;
const float kWarpMaxAlignTime = 5;
const float kWarpMinTime = 3;
const float kWarpMaxTime = 12;

/* Path cost of flying, in metres of normal flight: warp legs cost about as
   much as the time they take (aligning plus warping) would at cruise. */
const float kWarpAlignCost = 4000;
const float kCruiseSpeed = 400;

float WarpDuration(double length) {
  return Clamp(0.4f * Sqrt((float)(length / 1000.0)), kWarpMinTime, kWarpMaxTime);
}

float FlightCost(double distance) {
  if (distance < kWarpMinDistance)
    return (float)distance;
  return kWarpAlignCost + kCruiseSpeed * WarpDuration(distance);
}

enum WarpPhase {
  WarpPhase_None,
  WarpPhase_Align,
  WarpPhase_Warp
};

namespace {
  typedef Reference<struct PathNodeT> PathNode;

  AutoClass(Edge,
    PathNode, node,
    float, cost)
    Edge() {}
  };

  AutoClassDerived(PathNodeT, RefCounted,
    Object, object,
    Position, pos,
    float, distance,
    bool, visited,
    Vector<Edge>, edges,
    PathNode, prev)
    POOLED_TYPE

    PathNodeT() {}
    
    PathNodeT(Object const& object) :
      object(object),
      pos(object->GetPos()),
      distance(FLT_MAX),
      visited(false)
      {}
  };

  typedef Reference<struct PathT> Path;

  AutoClassDerived(PathT, RefCounted,
    Vector<Object>, nodes)
    PathT() {}
  };

  Path Path_Create(
    Object const& system,
    Object const& start,
    Object const& end)
  {
    Vector<PathNode> nodes;
    PathNode startNode = new PathNodeT(start);
    PathNode endNode = new PathNodeT(end);
    nodes.push(startNode);
    nodes.push(endNode);
    startNode->distance = 0;

    /* Construct path nodes. */ {
      Map<ObjectID, PathNode> idMap;

      for (InteriorIterator it = Object_GetInteriorObjects(system);
           it.HasMore(); it.Advance())
      {
        Object const& object = it.Get();
        ComponentNavigable* nav = object->GetNavigable();
        if (nav) {
          PathNode node = new PathNodeT(object);
          idMap[object->GetID()] = node;
          nodes.push(node);
        }
      }

      /* Connect edges. */
      for (size_t i = 0; i < nodes.size(); ++i) {
        PathNode const& node = nodes[i];

        /* Flying between nodes. */
        for (size_t j = 0; j < nodes.size(); ++j) {
          if (i == j)
            continue;
          PathNode const& other = nodes[j];
          node->edges.push(Edge(other, FlightCost(Length(other->pos - node->pos))));
        }

        /* Using special nodes. */
        ComponentNavigable* nav = node->object->GetNavigable();
        if (!nav)
          continue;

        for (size_t j = 0; j < nav->nodes.size(); ++j) {
          NavigableNode const& navNode = nav->nodes[j];

          /* Only consider connections in the same container! */
          if (navNode.dest->GetContainer() == system)
            node->edges.push(Edge(idMap[navNode.dest->GetID()], navNode.cost));
        }
      }
    }

    while (nodes.size()) {
      /* Pick closest node. */
      PathNode minNode;
      for (size_t i = 0; i < nodes.size(); ++i) {
        PathNode const& node = nodes[i];
        if (!minNode || node->distance < minNode->distance)
          minNode = node;
      }

      if (minNode == endNode)
        break;

      nodes.remove(minNode);

      /* Propagate distances through edges. */
      for (size_t i = 0; i < minNode->edges.size(); ++i) {
        Edge const& edge = minNode->edges[i];
        float distance = minNode->distance + edge.cost;
        if (distance < edge.node->distance) {
          edge.node->distance = distance;
          edge.node->prev = minNode;
        }
      }
    }

    /* No path was found. */
    if (!endNode->prev)
      return nullptr;

    Path path = new PathT;
    for (PathNode node = endNode; node && node != startNode; node = node->prev)
      path->nodes.push(node->object);
    return path;
  }

  AutoClass(TaskGotoInstance,
    Path, path,
    bool, flying,
    int, warpPhase,
    float, warpTime,
    float, warpDuration,
    Position, warpStart,
    Position, warpEnd)

    TaskGotoInstance() :
      flying(true),
      warpPhase(WarpPhase_None),
      warpTime(0),
      warpDuration(0),
      warpStart(0),
      warpEnd(0)
      {}

    void Advance() {
      if (path->nodes.size())
        path->nodes.pop();
    }

    Object GetNext() const {
      return (path && path->nodes.size()) ? path->nodes.back() : nullptr;
    }

    void Reset() {
      path = nullptr;
      flying = true;
      warpPhase = WarpPhase_None;
    }
  };

  /* Drive a warp toward 'node'; returns true while the warp is handling the
     ship's movement this frame. */
  bool UpdateWarp(
    Object const& self,
    TaskGotoInstance& it,
    Object const& node,
    float dt)
  {
    V3D toNode = (V3D)(node->GetCenter() - self->GetPos());
    double distance = Length(toNode);
    double exitDistance = node->GetRadius() + kWarpExitDistance;

    if (it.warpPhase == WarpPhase_None) {
      if (distance - exitDistance < kWarpMinDistance)
        return false;
      it.warpPhase = WarpPhase_Align;
      it.warpTime = 0;
    }

    V3 dir = (V3)(toNode / Max(distance, 1.0));

    if (it.warpPhase == WarpPhase_Align) {
      it.warpTime += dt;
      V3 velocity = self->GetVelocity();
      float speed = Length(velocity);
      bool aligned = speed > 0.25f * self->GetTopSpeed()
        && Dot(velocity / Max(speed, 1e-3f), dir) > 0.95f;

      if (!aligned && it.warpTime < kWarpMaxAlignTime) {
        /* Normal flight toward the node does the aligning. */
        return false;
      }

      it.warpPhase = WarpPhase_Warp;
      it.warpTime = 0;
      it.warpStart = self->GetPos();
      it.warpEnd = node->GetCenter() - (Position)(dir * (float)exitDistance);
      double length = Length((V3D)(it.warpEnd - it.warpStart));
      it.warpDuration = WarpDuration(length);
    }

    /* Warping. */
    it.warpTime += dt;
    float t = Saturate(it.warpTime / it.warpDuration);
    float s = t * t * (3 - 2 * t);
    self->SetPos(it.warpStart + (Position)((V3D)(it.warpEnd - it.warpStart) * (double)s));
    self->SetLook(Normalize((V3)(it.warpEnd - it.warpStart)));
    if (t >= 1)
      it.warpPhase = WarpPhase_None;
    return true;
  }

  AutoClassDerived(TaskGoto, TaskT, Task_Goto_Args, args)
    DERIVED_TYPE_EX(TaskGoto)
    POOLED_TYPE

    TaskGoto() {}

    String GetName() const {
      return "Goto";
    }

    Capability GetRateFactor() const {
      return Capability_Motion(1);
    }

    Object GetTarget() const {
      return args.target;
    }

    bool IsFinished(Object const& self, Data const&) const {
      return Condition_Nearby(self, args.target, args.distance);
    }

    void OnBegin(Object const& self, Data& data) {
      data = TaskGotoInstance();
    }

    void OnMessage(Object const& self, Data& data, Data& m) {
      if (m.type == Type_Get<MessageWaypoint>()) {
        TaskGotoInstance& it = data.Convert<TaskGotoInstance>();
        if (it.flying) {
          /* Huh?? How did I get a waypoint during flight? */
          it.Reset();
          return;
        }

        MessageWaypoint const& message = m.Convert<MessageWaypoint>();
        while (it.path->nodes.size() && it.path->nodes.back() != message.location)
          it.Advance();

        if (it.GetNext() == message.location) {
          it.Advance();

          /* Check if we want to break out of the nav path. */
          Object next = it.GetNext();
          if (next && !message.location->GetNavigable()->ConnectsTo(next))
            message.location->Send(MessageStopUsing(self));
        } else {
          /* Bad waypoint? */
          it.Reset();
          return;
        }
      }

      else if (m.type == Type_Get<MessageEjected>()) {
        TaskGotoInstance& it = data.Convert<TaskGotoInstance>();
        it.flying = true;
      }
    }

    void OnUpdate(Object const& self, float dt, Data& data) { AUTO_FRAME;
      TaskGotoInstance& it = data.Convert<TaskGotoInstance>();

      /* If we're not in the same container, need to figure out how to get
       * to the other one. */
      if (args.target->GetContainer() != self->GetContainer()) {
        /* We're in an immediate sub-container. */
        if (args.target->GetContainer() == self->GetContainer()->GetContainer()) {
          if (self->GetContainer()->GetDockable())
            self->GetContainer()->Undock(self);
          else {
            /* This case does not exist yet.  It's possible that it could,
             * though (pocket universes, for example). */
          }
        }

        else {
          /* This is where we will need to handle intersystem travel. */
          /* CRITICAL. */
        }
      }

      /* Else, we need to find the fastest way to get there in-system. */
      else {
        if (!it.path) {
          it.path = Path_Create(self->GetContainer().t, self, args.target);
          it.flying = true;
        }

        /* Move toward the next node. */ {
          Object nextNode = it.GetNext();
          if (nextNode && UpdateWarp(self, it, nextNode, dt))
            return;

          if (nextNode) {
            self->Broadcast(MessageBoost());
            self->GetMotionControl()->elements.push(
              SDF_Sphere(nextNode->GetCenter(), 1.0f));

            if (Length(nextNode->GetPos() - self->GetPos()) < 512.0f) {
              if (nextNode->GetNavigable()) {
                Object target = it.path->nodes[it.path->nodes.size() - 2];
                nextNode->Send(MessageStartUsing(self, target));
                it.flying = false;
              } else {
                it.Advance();
              }
            }
          }
        }

      }
    }
  };
}

DefineFunction(Task_Goto) {
  return new TaskGoto(args);
}
