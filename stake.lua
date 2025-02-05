local utils = require("modules.utils")

local initStaker = function (staker)
  if not Stakers[staker] then
    Stakers[staker] = {
      unclaim = 0, -- available to claim
      stake = {0,0}, -- count,amount
      yield = {0,0}, -- count,amount
      redeem = {0,0}, -- count,amount
      claims = {0,0}, -- count,amount
      stakings = {} -- active stakings
    }
  end
end

AESSET = AESSET or "Cge-oWlgN1b1uWR0pMJQmmJh8rV8F2wApd9ig6bDbbM"
STAKE_TOKEN = STAKE_TOKEN or "Cge-oWlgN1b1uWR0pMJQmmJh8rV8F2wApd9ig6bDbbM"
YIELD_TOKEN = YIELD_TOKEN or "KCAqEdXfGoWZNhtgPRIL0yGgWlCDUl0gvHu8dnE5EJs"

Name = Name or "stakedALT"
Ticker = Ticker or "sALT"
Logo = Logo or "bcwIgXwW2C1OMG8paTtDZtAVPp16cOQlvp3_qnS16eg"
Denomination = Denomination or 6
Balances = Balances or {}
Stakings = Stakings or {}
UnStakings = UnStakings or {}
Stakers = Stakers or {}
Funds = Funds or {}
Round = Round or 0

local yieldCalc = function (term, quantity)
  if term >= 16 then
    return 1 , quantity * 1
  elseif term >= 8 then
    return 0.4 , quantity * 0.4
  elseif term >= 2 then
    return 0.1 , quantity * 0.1
  else
    return 0 , quantity * 0
  end
end

-- Handlers.prepend("List-Quests", function (Msg)
--   return Msg.Action == "Test" and "continue"
-- end, function (Msg)
--   print("Test")
-- end)

-- Handlers.add("test","Test", function (mag)
--   print("Test 2")
-- end)

--[[
     Info
   ]]
--
Handlers.add('info', "Info", function(msg)
  msg.reply({
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination)
  })
end)


-- Statke
Handlers.stake = function (msg)
  print(msg.Id)
  local _quantity = tonumber(msg.Quantity)
  local _from = msg.Sender
  local _to = msg['X-To'] or msg.Sender
  local _term = msg['X-Term'] and tonumber(msg['X-Term']) or 16
  local _yield, _amount = yieldCalc(_term, _quantity)
  local _stake = {
    id = msg.Id,
    from = _from,
    to = _to,
    quantity = _quantity,
    term = _term,
    yield = _yield,
    amount = _amount,
    time = msg.Timestamp,
    start = Round,
    expire = Round + _term,
  }
  Stakings[msg.Id] = _stake
  -- table.insert(Stakings,_stake)
  if not Stakers[_from] then initStaker(_from) end
  table.insert(Stakers[_from].stakings,_stake.id)
  utils.increase(Stakers[_from].stake,{1,_stake.amount})
  if not Balances[_to] then Balances[_to] = 0 end
  Balances[_to] = Balances[_to] + _amount

  local stakeDebit = {
    Action = 'Stake-Debit',
    ['Stake-From'] = _stake.from,
    ['Stake-To'] = _stake.to,
    Quantity = msg.Quantity,
    Data = Colors.gray ..
        "You transferred " ..
        Colors.blue .. msg.Quantity .. Colors.gray .. " to " .. Colors.green .. msg.Recipient .. Colors.reset
  }
  -- Credit-Notice message template, that is sent to the Recipient of the transfer
  local stakeCredit = {
    Target = msg.Recipient,
    Action = 'Stake-Credit',
    Sender = msg.From,
    Quantity = msg.Quantity,
    Data = Colors.gray ..
        "You received " ..
        Colors.blue .. msg.Quantity .. Colors.gray .. " from " .. Colors.green .. msg.From .. Colors.reset
  }

  -- Add forwarded tags to the credit and debit notice messages
  for tagName, tagValue in pairs(msg) do
    -- Tags beginning with "X-" are forwarded
    if string.sub(tagName, 1, 2) == "X-" then
      debitNotice[tagName] = tagValue
      creditNotice[tagName] = tagValue
    end
  end
  
end

Handlers.add("stake",{
  From = STAKE_TOKEN,
  Action = "Credit-Notice",
  ['X-Transfer-Type'] = "Stake",
  Quantity = function (_q,msg)
    return tonumber(msg.Quantity) >= 1000000000000
  end
},Handlers.stake)

-- Redeem
Handlers.redeem = function (msg)
  print("Redeem")
end

Handlers.add("redeem",{Action="Redeem"},Handlers.redeem)


-- Queries

Handlers.add("get-staker",{
  Action="Get-Stakers",
  ['Staker-Id'] = "_"
},function (msg)
  local uid = msg['Staker-Id'] or msg.From
  local _data = utils.deepCopy(Stakers[uid])
  _data.balance = Balances[msg['Staker-Id']]
  msg.reply({Data = _data})
end)