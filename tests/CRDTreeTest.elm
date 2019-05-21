module CRDTreeTest exposing (..)

import Array exposing (Array)
import Dict exposing (Dict)

import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, intRange, list, string)
import Test exposing (..)
import List exposing (map, reverse)

import CRDTree exposing
  ( CRDTree
  , batch
  , delete
  , addBranch
  , add
  , apply
  , lastOperation
  , operationsSince
  , get
  )
import CRDTree.Node as Node exposing (Node, tombstone)
import CRDTree.Operation as Operation exposing (Operation(..))
import CRDTree.ReplicaId as ReplicaId exposing (ReplicaId)


suite : Test
suite = describe "CRDTree"
  [ testAdd "adds node"

  , testAddBranch
    "adds branch"

  , testAddToDeletedBranch "attempts to add to deleted branch"

  , testBatch
    "performs several operations"

  , testApplyBatch
    "applies several remote operations"

  , testBatchAtomicity
    "batch fails if an operation fails"

  , testAddIsIdempotent
    "applying Add multiple times is the same as once"

  , testInsertionBetweenNodes
    "apply Add inserts at any position"

  , testAddLeaf
    "inserts node as children of nested branch"

  , testDelete
    "Delete marks node as tombstone"

  , testDeleteIsIdempotent
    "apply same Delete operation yields same results"

  , testOperationsSince
    "gets operations since a timestamp"
  ]

testAdd description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      operation =
        Add replicaId 1 [0] "a"

      result =
        add "a" tree
  in
      describe description
        [ test "apply Add succeeds"
          <| always (Expect.ok result)

        , test "apply Add result updates tree nodes" <| \_ ->
          expectNode [1] (Just "a") result

        , test "apply Add sets tree operations" <| \_ ->
          let
              operations =
                  [ Add replicaId 1 [0] "a" ]
          in
              expectOperations operations result

        , test "sets last operation"
          <| always (expectLastOperation operation result)
        ]


testBatch description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      result =
        batch [add "a", add "b"] tree
  in
      describe description
        [ test "apply Batch succeeds"
          <| always (Expect.ok result)

        , test "apply Batch adds first node" <| \_ ->
          expectNode [1] (Just "a") result

        , test "apply Batch adds second node" <| \_ ->
          expectNode [2] (Just "b") result

        , test "apply Batch sets tree operations" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a"
                , Add replicaId 2 [1] "b"
                ]
          in
              expectOperations operations result

        , test "sets last operation" <| \_ ->
          let
              operation = Batch
                [ Add replicaId 1 [0] "a"
                , Add replicaId 2 [1] "b"
                ]
          in
              expectLastOperation operation result
        ]


testAddBranch description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      result =
        batch [addBranch "a", add "b"] tree
  in
      describe description
        [ test "apply Batch succeeds"
          <| always (Expect.ok result)

        , test "apply Batch adds branch child" <| \_ ->
          expectNode [1, 2] (Just "b") result

        , test "apply Batch sets tree operations" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a"
                , Add replicaId 2 [1, 0] "b"
                ]
          in
              expectOperations operations result

        , test "sets last operation" <| \_ ->
          let
              operation = Batch
                [ Add replicaId 1 [0] "a"
                , Add replicaId 2 [1, 0] "b"
                ]
          in
              expectLastOperation operation result
        ]


testAddToDeletedBranch description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Delete replicaId [1]
        , Add replicaId 2 [1, 0] "b"
        ]

      result =
        apply batch tree
  in
      describe description
        [ test "apply Batch succeeds"
          <| always (Expect.ok result)

        , test "apply Batch deletes branch" <| \_ ->
          expectNode [1] Nothing result

        , test "apply Batch sets tree operations" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a"
                , Delete replicaId [1]
                ]
          in
              expectOperations operations result

        , test "sets last operation" <| \_ ->
          let
              operation = Batch
                [ Add replicaId 1 [0] "a"
                , Delete replicaId [1]
                ]
          in
              expectLastOperation operation result
        ]


testApplyBatch description =
  let
      replicaId =
        ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Add replicaId 2 [1] "b"
        ]

      -- TODO: test concurrency by adding before and after batch

      result =
        apply batch tree
  in
      describe description
        [ test "apply Batch succeeds"
          <| always (Expect.ok result)

        , test "apply Batch adds first node" <| \_ ->
          expectNode [1] (Just "a") result

        , test "apply Batch adds second node" <| \_ ->
          expectNode [2] (Just "b") result

        , test "apply Batch sets tree operations" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a"
                , Add replicaId 2 [1] "b"
                ]
          in
              expectOperations operations result

        , test "sets last operation"
          <| always (expectLastOperation batch result)
        ]


testAddIsIdempotent description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Add replicaId 1 [0] "a"
        , Add replicaId 1 [0] "a"
        , Add replicaId 1 [0] "a"
        ]

      result =
        apply batch tree
  in
      describe description

        [ test "apply Add multiple times succeeds"
          <| always (Expect.ok result)

        , test "apply Add multiple times result updates tree nodes" <| \_ ->
          expectNode [1] (Just "a") result

        , test "apply Add multiple times sets tree operations" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a" ]
          in
              expectOperations operations result

        , test "sets last operation" <| \_ ->
          let
              operation = Batch
                [ Add replicaId 1 [0] "a" ]
          in
              expectLastOperation operation result
        ]


testInsertionBetweenNodes _ =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Add replicaId 2 [1] "c"
        , Add replicaId 3 [1] "b"
        ]

      result =
        apply batch tree
  in
      describe "apply Add inserts between nodes"
        [ test "apply Add insert succeeds"
          <| always (Expect.ok result)

        , test "apply Add insert adds first node" <| \_ ->
          expectNode [1] (Just "a") result

        , test "apply Add insert adds second node" <| \_ ->
          expectNode [2] (Just "c") result

        , test "apply Add insert adds third node" <| \_ ->
          expectNode [3] (Just "b") result

        , test "apply Add insert sets tree operations" <| \_ ->
          let
              operations =
                  [ Add replicaId 1 [0] "a"
                  , Add replicaId 2 [1] "c"
                  , Add replicaId 3 [1] "b"
                  ]
          in
              expectOperations operations result

        , test "sets last operation"
          <| always (expectLastOperation batch result)
        ]


testAddLeaf description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Add replicaId 2 [1, 0] "b"
        , Add replicaId 3 [1, 2] "c"
        ]

      result =
        apply batch tree
  in
      describe description
        [ test "apply Add leaf succeeds"
          <| always (Expect.ok result)

        , test "apply Add leaf adds first leaf" <| \_ ->
          expectNode [1, 2] (Just "b") result

        , test "apply Add leaf adds second leaf" <| \_ ->
          expectNode [1, 3] (Just "c") result

        , test "apply Add leaf sets tree operations" <| \_ ->
          let
              operations =
                  [ Add replicaId 1 [0] "a"
                  , Add replicaId 2 [1, 0] "b"
                  , Add replicaId 3 [1, 2] "c"
                  ]
          in
              expectOperations operations result

        , test "sets last operation"
          <| always (expectLastOperation batch result)
        ]


testBatchAtomicity description =
  test description <| \_ ->
    let
        replicaId = ReplicaId.fromInt 0

        tree =
          CRDTree.init
            { id = ReplicaId.toInt replicaId
            , maxReplicas = 1
            }

        batch = Batch
          [ Add replicaId 1 [0] "a"
          , Add replicaId 2 [9] "b"
          ]

        result =
          apply batch tree
    in
        Expect.err result


testDelete description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Delete replicaId [1]
        ]

      result =
        apply batch tree
  in
      describe description
        [ test "apply Add delete succeeds"
          <| always (Expect.ok result)

        , test "apply Delete result updates tree nodes" <| \_ ->
          expectNode [1] (Nothing) result

        , test "sets last operation"
          <| always (expectLastOperation batch result)
        ]


testDeleteIsIdempotent description =
  let
      replicaId = ReplicaId.fromInt 0

      tree =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Delete replicaId [1]
        , Delete replicaId [1]
        , Delete replicaId [1]
        , Delete replicaId [1]
        , Delete replicaId [1]
        ]

      result =
        apply batch tree
  in
      describe description

        [ test "apply Add multiple times succeeds"
          <| always (Expect.ok result)

        , test "apply Add multiple times result updates tree nodes" <| \_ ->
          expectNode [1] Nothing result

        , test "apply Add multiple times sets tree operations" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a"
                , Delete replicaId [1]
                ]
          in
              expectOperations operations result

        , test "sets last operation" <| \_ ->
          let
              operation = Batch
                [ Add replicaId 1 [0] "a"
                , Delete replicaId [1]
                ]
          in
              expectLastOperation operation result
        ]


testOperationsSince description =
  let
      replicaId =
        ReplicaId.fromInt 0

      tree2 =
        CRDTree.init
          { id = ReplicaId.toInt replicaId
          , maxReplicas = 1
          }

      batch = Batch
        [ Add replicaId 1 [0] "a"
        , Add replicaId 2 [1] "b"
        , Add replicaId 3 [2] "c"
        , Add replicaId 4 [3] "d"
        , Delete replicaId [3]
        , Batch []
        , Add replicaId 5 [4] "e"
        , Add replicaId 6 [5] "f"
        ]

      tree =
        apply batch tree2 |> Result.withDefault tree2
  in
      describe description
        [ test "operations since beginning" <| \_ ->
          let
              operations =
                [ Add replicaId 1 [0] "a"
                , Add replicaId 2 [1] "b"
                , Add replicaId 3 [2] "c"
                , Add replicaId 4 [3] "d"
                , Delete replicaId [3]
                , Add replicaId 5 [4] "e"
                , Add replicaId 6 [5] "f"
                ]
          in
              Expect.equal operations
                <| operationsSince 0 tree

        , test "operations since 2" <| \_ ->
          let
              operations =
                [ Add replicaId 2 [1] "b"
                , Add replicaId 3 [2] "c"
                , Add replicaId 4 [3] "d"
                , Delete replicaId [3]
                , Add replicaId 5 [4] "e"
                , Add replicaId 6 [5] "f"
                ]
          in
              Expect.equal operations
                <| operationsSince 2 tree

        , test "operations since last" <| \_ ->
          let
              operations =
                [ Add replicaId 6 [5] "f" ]
          in
              Expect.equal operations
                <| operationsSince 6 tree

        , test "not present returns empty" <| \_ ->
          Expect.equal [] <| operationsSince 10 tree
        ]


expectNode path exp result =
  expect (\tree ->
    Expect.equal exp (get path tree)) result


expectOperations exp result =
  expect (\tree -> Expect.equal exp (operationsSince 0 tree)) result


expectLastOperation exp result =
  expect (\tree -> Expect.equal exp (lastOperation tree)) result


expect fun result =
  Result.map fun result
    |> Result.withDefault (Expect.fail "failed")

