local utils = require("modules.utils")
local json = require('json')

STAKE_MIN_DURATION = STAKE_MIN_DURATION or 604800000 -- 7 days
STAKE_MAX_DURATION = STAKE_MAX_DURATION or 124416000000 -- 4 years
STAKE_TOKEN = STAKE_TOKEN or "<STAKE_TOKEN>"
Name = Name or "<NAME>"
Ticker = Ticker or "<TICKER>"
Logo = Logo or "bcwIgXwW2C1OMG8paTtDZtAVPp16cOQlvp3_qnS16eg"
Denomination = Denomination or "<DENOMINATION>"


Stakers = Stakers or {} -- key: userAddress val: {amount=100,start_time = 1741059382183, locked_time = 2*366*24*60*60*1000}
State = State or {
  stake_amount = {0,0}, -- {balance,total},
  stakers = 0,
  latest_stake = 0,
}
Funds = Funds or  {}

utils.initStaker = function (uid)
  if not Stakers[uid] then
    Stakers[uid] = {
      amount = 0,
      start_time = nil,
      locked_time = nil
    }
  end
end

utils.sumStakedAmount = function()
  local total = '0'
  for _, user in pairs(Stakers) do
    total = utils.add(total, user.amount)
  end
  return total
end

utils.veBalance = function(uid, ts)
  local user = Stakers[uid]
  if not user then
      return '0'
  end

  local left_time = math.max(user.locked_time - (ts - user.start_time),0)
  if left_time <= 0 then
      return '0'
  end

  local result = user.amount * math.min(left_time / STAKE_MAX_DURATION,1)
  return string.format("%.0f", result)
end

utils.getBalances = function(ts)
  local total = "0"
  local balances = {}
  for address in pairs(Stakers) do
      local bal = utils.veBalance(address, ts)
      balances[address] = bal
      total = utils.add(total,bal)
  end
  return balances, total
end

utils.totalSupply = function(ts)
  local balances = utils.getBalances(ts)
  local totalSupply = '0'
  for _, bal in pairs(balances) do
      totalSupply = utils.add(totalSupply, bal)
  end
  return totalSupply
end

utils.calUnstakeAmount = function (uid,ts)
  local staker = Stakers[uid]
  local r = math.min((ts - staker.start_time) / staker.locked_time,1)
  return math.floor(staker.amount * r), math.floor(staker.amount * (1-r))
end

Handlers.add("stake",{
  Action = "Credit-Notice",
  From = function (_from) return _from == STAKE_TOKEN end,
  ['X-Transfer-Type'] = "Stake",
  ['X-Locked-Time'] = "%d+",
  Quantity = "%d+"
}, function(msg)
  print("Stake")
  assert(tonumber(msg.Quantity)>=1,"The stake amount must be greater than or equal to 1")
  local start_time = msg.Timestamp
  local new_locked_time = math.max(tonumber(msg['X-Locked-Time']),STAKE_MIN_DURATION)
  local locked_time
  if not Stakers[msg.Sender] then 
    utils.initStaker(msg.Sender)
    utils.increase(State,{stakers=1})
    locked_time = new_locked_time
  else
    locked_time = math.max(new_locked_time or STAKE_MIN_DURATION,Stakers[msg.Sender].locked_time)
  end
  
  utils.increase(Stakers[msg.Sender],{amount = tonumber(msg.Quantity)})
  utils.increase(State.stake_amount,{tonumber(msg.Quantity),tonumber(msg.Quantity)})
  utils.update(Stakers[msg.Sender],{start_time = start_time,locked_time = locked_time})
  utils.update(State,{latest_stake = msg.Timestamp})
  local tags = {
    Quantity = msg.Quantity,
    Staker = msg.Sender,
    ['Asset-Id'] = msg.From,
    ['Start-Time'] = tostring(start_time),
    ['Locked-Time'] = tostring(locked_time),
    ['Pushed-For'] = msg['Pushed-For'],
    Data = {msg.Quantity,start_time,locked_time}
  }
  local stake_notice = utils.deepCopy(tags)
  stake_notice.Action = "Stake-Notice"
  msg.reply(stake_notice)
  local staked = utils.deepCopy(tags)
  staked.Action = "Staked"
  staked.Target = msg.Sender
  Send(staked)
  
end)


Handlers.add("unstake",{
  Action = "Unstake",
},function(msg)
  assert(Stakers[msg.From]~=nil,"Staker not exist!")
  assert(Stakers[msg.From].amount >= 0, "Insufficient amount")
  local refund, burn = utils.calUnstakeAmount(msg.From, msg.Timestamp)
  assert(refund >= 1, "The amount must be greater than 1")
  if refund >= 1 then
    print("refund:"..refund)
    local msg_stake = {
      Target = STAKE_TOKEN,
      Action = "Transfer",
      Recipient = msg.From,
      Quantity = string.format("%.0f", refund),
      ['X-Transfer-Type'] = "Unstaked",
      ['X-Unstake-Amount'] = string.format("%.0f", Stakers[msg.From].amount),
      ['X-Staker'] = msg.From
    }
    print(msg_stake)
    Send(msg_stake)
  end

  if burn >= 1 then
    print("burn:"..burn)
    local msg_burn = {
      Target = STAKE_TOKEN,
      Action = "Burn",
      Quantity = string.format("%.0f", burn),
    }
    print(msg_burn)
    Send(msg_burn).onReply(function (m)
      utils.increase(State,{burned = burn})
    end)
    
  end

  utils.decrease(State.stake_amount,{Stakers[msg.From].amount,0})
  utils.decrease(State,{stakers = 1})
  utils.update(State,{latest_unstake = msg.Timestamp})
  Stakers[msg.From] = nil

end)

Handlers.add("balances", "Balances", function(msg)
  local Balances, Total = utils.getBalances(msg.Timestamp)
  msg.reply({
      Total = Total,
      Data = json.encode(Balances)
  })
end)

Handlers.add("balance", "Balance", function(msg)
  local Balances,Total = utils.getBalances(msg.Timestamp)

  local bal = '0'
  -- If not Recipient is provided, then return the Senders balance
  if (msg.Tags.Recipient) then
      if (Balances[msg.Tags.Recipient]) then
          bal = Balances[msg.Tags.Recipient]
      end
  elseif msg.Tags.Target and Balances[msg.Tags.Target] then
      bal = Balances[msg.Tags.Target]
  elseif Balances[msg.From] then
      bal = Balances[msg.From]
  end

  msg.reply({
      Total = Total,
      Balance = bal,
      Ticker = Ticker,
      Account = msg.Tags.Recipient or msg.From,
      Data = bal
  })
end)

Handlers.add("info", "Info", function(msg)
  msg.reply({
      Name = Name,
      Ticker = Ticker,
      Logo = Logo,
      Denomination = tostring(Denomination),
      Staked = utils.sumStakedAmount(),
      TotalSupply = utils.totalSupply(msg.Timestamp)
  })
end)

Handlers.add("state","State",function (msg)
  local _state = utils.deepCopy(State)
  _state.total_supply = utils.totalSupply(msg.Timestamp)
  msg.reply({
    Data = _state
  })
end)




Handlers.add("get",{
  Action = "Get"
},{
  [{Tab="Stakers",['Address'] = "_"}] = function (msg)
    assert(Stakers[msg.Address]~=nil,"the staker does not exist")
    local staker = utils.deepCopy(Stakers[msg.Address])
    staker.balance = utils.veBalance(msg.Address,msg.Timestamp)
    
    msg.reply({
      Action="Getted",
      Tab = "Stakers",
      Data = staker
    })
  end
})



Handlers.prepend("cash_flow", function (msg) return "continue" end, function (msg)
  if msg.Action == "Credit-Notice" or msg.Action == "Debit-Notice" then
    print("cashFlow")
    if not Funds then Funds = {} end
    if not Funds[msg.From] then 
      Funds[msg.From] = {
        bal=0,
        income=0,
        outcome=0
      }
    end
    utils.increase(Funds[msg.From],{
      bal = msg.Action == "Credit-Notice" and tonumber(msg.Quantity) or -tonumber(msg.Quantity),
      income = msg.Action == "Credit-Notice" and tonumber(msg.Quantity) or 0,
      outcome = msg.Action == "Debit-Notice" and tonumber(msg.Quantity) or 0
    })
  end
end)


--- ALC boost