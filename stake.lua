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

  local left_time = user.locked_time - (ts - user.start_time)
  if left_time <= 0 then
      return '0'
  end

  -- local a = utils.multiply(string.format("%.0f", user.amount), left_time)
  -- local b = utils.divide(a, STAKE_MAX_DURATION)
  local result = user.amount * (left_time / STAKE_MAX_DURATION)
  return string.format("%.0f", result)
end

utils.getBalances = function(ts)
  local balances = {}
  for address in pairs(Stakers) do
      local bal = utils.veBalance(address, ts)
      balances[address] = bal
  end
  return balances
end

utils.totalSupply = function(ts)
  local balances = utils.getBalances(ts)
  local totalSupply = '0'
  for _, bal in pairs(balances) do
      totalSupply = utils.add(totalSupply, bal)
  end
  return totalSupply
end

utils.calUnstakeAmount = function (uid , ts)
  local staker = Stakers[uid]
  local r = math.min((ts - staker.start_time) / STAKE_MAX_DURATION,0)
  return math.floor(staker.amount * r), math.floor(staker.amount * (1-r))
end

Handlers.add("stake",{
  Action = "Credit-Notice",
  From = function (_from) return _from == STAKE_TOKEN end,
  ['X-Transfer-Type'] = "Stake",
  ['X-Locked-Time'] = "%d+",
  Quantity = "%d+"
}, function(msg)
  assert(tonumber(msg.Quantity)>=1,"The stake amount must be greater than or equal to 1")
  local start_time = msg.Timestamp
  local locked_time = math.max(tonumber(msg['X-Locked-Time']),STAKE_MIN_DURATION)
  if not Stakers[msg.Sender] then 
    utils.initStaker(msg.Sender)
    utils.increase(State,{stakers=1})
  end
  utils.increase(Stakers[msg.Sender],{amount = tonumber(msg.Quantity)})
  utils.increase(State,{stake_amount = tonumber(msg.Quantity)})
  utils.update(Stakers[msg.Sender],{start_time = start_time,locked_time = locked_time})
  utils.update(State,{latest_stake = msg.Timestamp})
  local tags = {
    Action = "Staked",
    Quantity = msg.Quantity,
    Staker = msg.Sender,
    ['Asset-Id'] = msg.From,
    ['Start-Time'] = tostring(start_time),
    ['Locked-Time'] = tostring(locked_time),
    ['Pushed-For'] = msg['Pushed-For'],
    Data = {msg.Quantity,start_time,locked_time}
  }
  
  msg.reply(tags)
  tags.Target = msg.Sender
  Send(tags)
  
end)


Handlers.add("unstake",{
  Action = "Unstake",
},function(msg)
  assert(Stakers[msg.From]~=nil,"Staker not exist!")
  assert(Stakers[msg.From].amount >= 0, "Insufficient amount")
  local released, unreleased = utils.calUnstakeAmount(msg.From, msg.Timestamp)
  if released >= 1 then
    Send({
      Target = STAKE_TOKEN,
      Action = "Transfer",
      Recipient = msg.From,
      Quantity = string.format("%.0f", released),
      ['X-Transfer-Type'] = "Unstake",
      ['Pushed-For'] = msg['Pushed-For']
    })
  end

  if unreleased >= 1 then
    Send({
      Target = STAKE_TOKEN,
      Action = "Burn",
      Quantity = string.format("%.0f", released),
    })
  end

  utils.decrease(State,{stake_amount = Stakers[msg.From].amount,stakers = 1})
  utils.update(State,{latest_unstake = msg.Timestamp})
  Stakers[msg.From] = nil
  

end)

Handlers.add("balances", "Balances", function(msg)
  local Balances = utils.getBalances(msg.Timestamp)
  msg.reply({
      Data = json.encode(Balances)
  })
end)

Handlers.add("balance", "Balance", function(msg)
  local Balances = utils.getBalances(msg.Timestamp)

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