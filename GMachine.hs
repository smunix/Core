module GMachine where

import Types
import Parser
import qualified Data.Map as M (lookup, insert)

--runProg :: [Char] -> [Char]
--runProg = showResults . compile . parse


--------------------------- GET/SET GMSTATE ---------------------------

getOutput :: GmState -> GmOutput
getOutput (o,i ,stack, dump, vstack, heap, globals, stats) = o

putOutput :: GmOutput -> GmState -> GmState
putOutput newO (output, code, stack, dump, vstack, heap, globals, stats) =
 (newO, code, stack, dump, vstack, heap, globals, stats)

getCode :: GmState -> GmCode
getCode (output, code, stack, dump, vstack, heap, globals, stats) = code

putCode :: GmCode -> GmState -> GmState
putCode newCode (output, oldCode, stack, dump, vstack, heap, globals, stats) =
 (output, newCode, stack, dump, vstack, heap, globals, stats)

getStack :: GmState -> GmStack
getStack (output, i, stack, dump, vstack, heap, globals, stats) = stack

putStack :: GmStack -> GmState -> GmState
putStack newStack (output, i, oldStack, dump, vstack, heap, globals, stats) =
 (output, i, newStack, dump, vstack, heap, globals, stats)

getDump :: GmState -> GmDump
getDump (output, i, stack, dump, vstack, heap, globals, stats) = dump

putDump :: GmDump -> GmState -> GmState
putDump newDump (output, i, stack, dump, vstack, heap, globals, stats) =
 (output, i, stack, newDump, vstack, heap, globals, stats)

getVStack :: GmState -> GmVStack
getVStack (o, i, stack, dump, vstack, heap, globals, stats) = vstack

putVStack :: GmVStack -> GmState -> GmState
putVStack newVstack (o, i, stack, dump, vstack, heap, globals, stats) =
 (o, i, stack, dump, newVstack, heap, globals, stats)

getHeap :: GmState -> GmHeap
getHeap (output, i, stack, dump, vstack, heap, globals, stats) = heap

putHeap :: GmHeap -> GmState -> GmState
putHeap newHeap (output, i, stack, dump, vstack, oldHeap, globals, stats) =
 (output, i, stack, dump, vstack, newHeap, globals, stats)

getGlobals :: GmState -> GmGlobals
getGlobals (output, i, stack, dump, vstack, heap, globals, stats) = globals

putGlobals :: Name -> Addr -> GmState -> GmState
putGlobals name addr (output, code, stack, dump, vstack, heap, globals, stats) = 
  let newGlobals = M.insert name addr globals
  in (output, code, stack, dump, vstack, heap, newGlobals, stats)

getStats :: GmState -> GmStats
getStats (output, i, stack, dump, vstack, heap, globals, stats) = stats

putStats :: GmStats -> GmState -> GmState
putStats newStats (output, i, stack, dump, vstack, heap, globals, oldStats) =
 (output, i, stack, dump, vstack, heap, globals, newStats)

statInitial :: GmStats
statInitial = 0

statIncSteps :: GmStats -> GmStats
statIncSteps s = s+1

statGetSteps :: GmStats -> Int
statGetSteps s = s

--------------------------- HEAP FUNCTIONS ---------------------------
hInitial :: Heap a
hInitial = (0, 1, [])

-- pairs the next free address with the supplied node
-- increases the size of the heap by 1
-- adds the pair to the heap
-- returns the new heap and the new address that was added
hAlloc :: Heap a -> a -> (Heap a, Addr)
hAlloc (size, address, cts) n = ((size+1, address+1, (address,n) : cts),address)

-- replaces a the node at address "a" with a new node "n"
-- TODO: see remove function
hUpdate :: Heap a -> Addr -> a -> Heap a
hUpdate (size, free, cts) a n = (size, free, (a,n) : remove cts a)

-- removes a (Name,Address) pair
-- adds the address back to the available list
--hFree :: Heap a -> Addr -> Heap a
--hFree (size, free, cts) a = (size-1, a:free, remove cts a)

-- looks up a node in a heap
hLookup :: Heap Node -> Addr -> Maybe Node
hLookup (size,free,cts) a = lookup a cts

-- returns the addresses from the paired (Name, Address) list
hAddresses :: Heap a -> [Addr]
hAddresses (size, free, cts) = [addr | (addr, node) <- cts]

hSize :: Heap a -> Int
hSize (size, free, cts) = size

hNull :: Addr
hNull = 0

hIsnull :: Addr -> Bool
hIsnull a = a == 0

showaddr :: Addr -> [Char]
showaddr a = "#" ++ show a

-- TODO: account for failure
remove :: [(Int,a)] -> Int -> [(Int,a)]
remove [] a = []
remove ((val,n):cts) match | match == val = cts
                      | match /= val = (val,n) : remove cts match

--------------------------- EVALUATOR ---------------------------

-- executes the g-machine by executing each instruction
-- each execution of an instruction is cons'ed to the list
-- the last state in the list is the final instruction
eval :: GmState -> [GmState]
eval state = state : restStates where
    restStates | gmFinal state = []
               | otherwise     = eval nextState
    nextState = doAdmin (step state)

-- increases the statistics, puts the new value into the state
doAdmin :: GmState -> GmState
doAdmin s = putStats (statIncSteps (getStats s)) s

-- checks to see if the current state is the final one
-- the state is final if all of the code has been executed
gmFinal :: GmState -> Bool
gmFinal s = case (getCode s) of []        -> True
                                otherwise -> False

-- makes a state transistion based on the instruction
-- takes out the current instruction from the instruction list
step :: GmState -> GmState
step state = dispatch i (putCode is state) where
    (i:is) = getCode state

-- executes the current instruction
-- moves the machine to the next state
dispatch :: Instruction -> GmState -> GmState
dispatch (Pushglobal f) = pushglobal f
dispatch (Pushint n) = pushint n
dispatch (Pushbasic n) = pushbasic n
dispatch Mkap = mkap
dispatch Mkint = mkInt
dispatch Mkbool = mkBool
dispatch (Push n) = push n
dispatch (Pop n) = pop n
dispatch (Update n) = update n
dispatch Unwind = unwind
dispatch (Slide n) = slide n
dispatch (Alloc n) = alloc n
dispatch Eval = evalI
dispatch Add = add
dispatch Sub = sub
dispatch Mul = mul
dispatch Div = divide
dispatch Neg = neg
dispatch Eq = eq
dispatch Ne = ne
dispatch Lt = lt
dispatch Le = le
dispatch Gt = gt
dispatch Ge = ge
dispatch (Cond c1 c2) = cond c1 c2
dispatch (Pack t n) = pack t n
dispatch (Casejump cases) = casejump cases
dispatch (Split n) = split n
dispatch Print = printt
dispatch Get = get

-- finds a unique global node in the heap
-- puts the address of the global node at the top of the stack
pushglobal :: Name -> GmState -> GmState
pushglobal f state =  let a = M.lookup f (getGlobals state) in
  case a of Just add -> putStack (add: getStack state) state
            Nothing  -> error ("pushglobal: global " ++ f ++ " not found in globals")
 
-- pushes an integer node onto the heap
pushint :: Int -> GmState -> GmState
pushint n state = 
  let maybeAddr = M.lookup (show n) (getGlobals state)
      pushintHelper s = putHeap newHeap (putStack (a: getStack s) s)
      (newHeap, a) = hAlloc (getHeap state) (NNum n) in
  case maybeAddr of Just addr -> (putStack (addr: getStack state) state) where
                    Nothing -> pushintHelper $ putGlobals (show n) a state

-- takes the 2 addresses at the top of the address stack
-- and combines them into one address
-- also constructs an application node and puts it in the heap
mkap :: GmState -> GmState
mkap state =
 putHeap newHeap (putStack (newAddress:addresses) state) where
  (newHeap, newAddress) = hAlloc (getHeap state) (NAp a1 a2)
  (a1:a2:addresses) = getStack state

-- gets the current address stack
-- pushes the A(nth) address on top of the stack
push :: Int -> GmState -> GmState
push n state = 
  let as = getStack state
      a = (as !! n) in putStack (a:as) state

-- takes the address at the top of the stack
-- drops the next n addresses from the stack
-- reattaches the address to the stack
slide :: Int -> GmState -> GmState
slide n state = putStack (a : drop n as) state where
  (a:as) = getStack state

update :: Int -> GmState -> GmState
update n state = 
  let (a:as) = getStack state
  in putHeap (hUpdate (getHeap state) (as !! n) (NInd a)) (putStack as state)

-- TODO: better error handling
getArg :: Node -> Maybe Addr
getArg (NAp a1 a2) = return a2

-- takes the address at the top of the stack
-- drops the next n addresses from the stack
-- reattaches the address to the stack
pop :: Int -> GmState -> GmState
pop n state = putStack (drop n stack) state where
  stack = getStack state

-- always the last section
-- if NNum then the g-machine has terminated
-- if NAp then we continue to unwind from the next node
-- if NGlobal then we put it's code to the state and continue
unwind :: GmState -> GmState
unwind state = 
  let stack@(a:as) = getStack state
      dump = getDump state
      heap = getHeap state
      replaceAddrs name = putStack (rearrange name heap stack)
      n = (hLookup heap a)
      newState (NNum num) = updateFromDump a dump state
      newState (NConstr t s) = updateFromDump a dump state
      newState (NAp a1 a2) = putCode [Unwind] (putStack (a1:a:as) state)
      newState (NInd ia) = putCode [Unwind] (putStack (ia:as) state)
      newState (NGlobal na c) | length as < na = 
        case dump of ((i,s):d) -> putCode i $
                                  putStack ((last stack):s) $
                                  putDump d state
                     []        -> error "unwind: dump should not be empty"
                              | otherwise =
        replaceAddrs na $ putCode c state in
      case n of Just node -> newState node        
                Nothing -> error "unwind: address not found in heap"

updateFromDump :: Addr -> GmDump -> GmState -> GmState
updateFromDump address dump state = 
  case dump of [] -> state
               ((i,s):d) -> putDump d $ 
                            putCode i $
                            putStack (address:s) state

-- replaces the application node addresses in the stack with
-- the addresses of the value being applied to
rearrange :: Int -> GmHeap -> GmStack -> GmStack
rearrange n heap as = 
  let newAs = mapM ((getArg =<<) . hLookup heap) (tail as) in
  case newAs of Just addrs -> take n addrs ++ drop n as
                Nothing -> error "rearrange: address not found in heap" 
  
evalI :: GmState -> GmState
evalI state = 
  let code = getCode state
      (a:as) = getStack state
      dump = getDump state in
  putCode [Unwind] $ putStack [a] $ putDump ((code, as):dump) state

alloc :: Int -> GmState -> GmState
alloc n state = let (newHeap, addrs) = allocNodes n (getHeap state)
                    stack = getStack state in
  putHeap newHeap $ putStack (addrs ++ stack) state

allocNodes :: Int -> GmHeap -> (GmHeap, [Addr])
allocNodes 0 heap = (heap, [])
allocNodes n heap = (heap2, a:as) where
  (heap1, as) = allocNodes (n-1) heap
  (heap2, a) = hAlloc heap1 (NInd hNull)


boxInteger :: Int -> GmState -> GmState
boxInteger n state = 
  putVStack (a: getVStack state) $ putHeap newHeap state where
    (newHeap, a) = hAlloc (getHeap state) (NNum n)

boxBoolean :: Bool -> GmState -> GmState
boxBoolean b state =
  putVStack (a: getVStack state) $ putHeap newHeap state where
    (newHeap, a) = hAlloc (getHeap state) (NConstr bool [])
    bool | b = 2
         | otherwise = 1

comparison :: (Int -> Int -> Bool) -> StateTran
comparison op state = 
  let (a0:a1:as) = getVStack state
      bool = (a0 `op` a1)
      vBool n = putVStack (n:as) state in
  if bool then vBool 2 else vBool 1    

arithmetic1 :: MOperator Int Int -> StateTran
arithmetic1 op state = putVStack (op a : v) state where
  (a:v) = getVStack state

arithmetic2 :: DOperator Int Int -> StateTran
arithmetic2 op state = putVStack ((a0 `op` a1):as) state where
    (a0:a1:as) = getVStack state

cond :: GmCode -> GmCode -> GmState -> GmState
cond t f state =
  let (n:v) = getVStack state
      i = getCode state in
  case n of 2 -> putCode (t++i) $ putVStack v state
            1 -> putCode (f++i) $ putVStack v state
            _ -> error $ "cond: the number " ++ show n ++ " is not valid"


add :: GmState -> GmState
add state = arithmetic2 (+) state

sub :: GmState -> GmState
sub state = arithmetic2 (-) state

divide :: GmState -> GmState
divide state = arithmetic2 (div) state

mul :: GmState -> GmState
mul state = arithmetic2 (*) state

neg :: GmState -> GmState
neg state = arithmetic1 (* (-1)) state

eq :: GmState -> GmState
eq state = comparison (==) state

ne :: GmState -> GmState
ne state = comparison (/=) state

le :: GmState -> GmState
le state = comparison (<=) state

lt :: GmState -> GmState
lt state = comparison (<) state

gt :: GmState -> GmState
gt state = comparison (>) state

ge :: GmState -> GmState
ge state = comparison (>=) state

pack :: Int -> Int -> GmState -> GmState
pack t n state = 
  let stack = getStack state
      heap = getHeap state
      (newHeap, a) = hAlloc heap (NConstr t (take n stack)) in 
  putStack (a:(drop n stack)) $ putHeap newHeap state

casejump :: [(Int, GmCode)] -> GmState -> GmState
casejump cases state =
  let (a:s) = getStack state
      i = getCode state
      heap = getHeap state
      maybeNode = hLookup heap a
      maybeCode typ = lookup typ cases
      message t = "code for <" ++ show t ++ "> not found in cases"
      typeCode t = case (maybeCode t) of Just code -> code
                                         _         -> error (message t) in 
  case maybeNode of Just (NConstr t ss) -> putCode ((typeCode t)++i) state
                    _ -> error "casejump: node not found in heap"

split :: Int -> GmState -> GmState
split n state = 
  let (a:as) = getStack state
      heap = getHeap state
      maybeNC = hLookup heap a in 
  case maybeNC of Just (NConstr t s) -> putStack (s++as) state
                  _ -> error "split: node not found in heap"

printt :: GmState -> GmState
printt state = 
  let (a:as) = getStack state
      heap = getHeap state
      output = getOutput state
      i = getCode state
      appP xs = take (2 * (length xs)) $ cycle [Eval, Print]
      maybeNode = hLookup heap a in 
  case maybeNode of 
    Just (NNum n) -> putStack as $ putOutput (output ++ (show n)) state
    Just (NConstr t s) -> putOutput ("<" ++ show t ++ "> ") $ putCode ((appP s)++i) $ putStack (s++as) state
    _ -> error $ "address " ++ show a ++ " not found in heap"

pushbasic :: Int -> GmState -> GmState
pushbasic n state = 
  let vstack = getVStack state in putVStack (n:vstack) state

mkBool :: GmState -> GmState
mkBool state = 
  let stack = getStack state
      heap = getHeap state
      (t:v) = getVStack state
      (newHeap, add) = hAlloc heap (NConstr t [])
  in putVStack v $ putStack (add:stack) $ putHeap newHeap state

mkInt :: GmState -> GmState
mkInt state = 
  let stack = getStack state
      heap = getHeap state
      (n:v) = getVStack state
      (newHeap, add) = hAlloc heap (NNum n)
  in putVStack v $ putStack (add:stack) $ putHeap newHeap state

get :: GmState -> GmState
get state = 
  let (a:as) = getStack state
      heap = getHeap state
      maybeNode = hLookup heap a
      v = getVStack state
      getH val = putStack as $ putVStack (val:v) state
  in case maybeNode of Just (NConstr t _) -> getH t
                       Just (NNum n)      -> getH n
                       _ -> error "get: node not found in heap"
