local utils = require("modules.utils")
AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT>"
OPREATOR = OPREATOR or "j0Lrrv1ltimsYnD_5f-8Fp3QKcAbUjckn7kjCZCfvhk"
STAKE_ID = STAKE_ID or "kqDiKjXCwO16RJmjJqSNDbqdMVbrCaplEh7KnUHinlA"
WUSDC = WUSDC or "7zH9dlMNoxprab9loshv3Y7WG45DOny_Vrq9KrXObdQ"


Funds = Funds or {}
Bills = Bills or {}
State = State or {}

Handlers.add("info","Info",function(msg)
  msg.reply({
    Agent = AGENT
  })
end)

Handlers.append("cash_flow", {Action = function (action)
  return action == "Debit-Notice" or action == "Credit-Notice"  
end}, function (msg)
  local bill = {
    Id = msg.Id,
    Action = msg.Action,
    Quantity = msg.Quantity,
    Token = msg.From,
    Recipient = msg.Recipient,
    Sender = msg.Sender
  }

  -- Add forwarded tags to the credit and debit notice messages
  for tagName, tagValue in pairs(msg) do
    -- Tags beginning with "X-" are forwarded
    if string.sub(tagName, 1, 2) == "X-" then
      bill[tagName] = tagValue
    end
  end

  if not Bills then Bills = {} end
  table.insert(Bills,bill)
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
  print(bill)
end)

Handlers.transferToOP = function (token,amount)
  assert(Funds[token]~=nil,"missed the token funds")
  local _bal = Funds[token].bal
  local _amount = 0
  if amount and type(amount) == "number" then
    _amount = math.min(amount,_bal)
  else
    _amount = _bal
  end
  local recipient = OPREATOR or "j0Lrrv1ltimsYnD_5f-8Fp3QKcAbUjckn7kjCZCfvhk"
  Send({
    Target = token,
    Action = "Transfer",
    Recipient = recipient,
    Quantity = string.format("%0.f",_amount),
    ['X-Transfer-Type'] = "transferToOP"
  })
end

-- dao management
DAO = DAO or { _version = "0.0.1" }


DAO.payALT = function (shareholders)
  assert(type(shareholders) == "table" and shareholders~=nil, "missed shareholders or type error")
  local pid = AGENT
  local _supply
  local _balance
  local _income
  if not DAO.payroll then DAO.payroll = {} end
  if not DAO.payroll[pid] then DAO.payroll[pid] = {ref=0} end
  Send({
    Target = pid,
    Action = "Total-Supply"
  }).onReply(function (m)
    _supply = tonumber(m.Data)
    _income = (_supply - (DAO.payroll[pid].supply or 0))*0.2
    Funds[pid].income = Funds[pid].income + _income
    Send({
      Target = pid,
      Action = "Balance",
      Recipient = ao.id
    }).onReply(function (m1)
      _balance = tonumber(m1.Data)
      Funds[pid].bal = _balance
      local _total_pay = 0
      local payouts = {}
      for _, user in ipairs(shareholders) do
        local _amount = _income * user.rate
        payouts[user.address] = _amount
        _total_pay = _total_pay + _amount
      end
      assert(_balance >= _total_pay, "insufficient balance")
      

      for key, value in pairs(payouts) do
        print(key..":"..string.format("%0.f",value))
        local tags = {
          Target = pid,
          Action = "Transfer",
          Quantity = string.format("%0.f",value),
          Recipient = key,
          ['X-Transfer-Type'] = "Payroll",
          ['X-Payroll-Ref'] = tostring(DAO.payroll[pid].ref + 1),
          ['X-Payroll-Settled'] =  string.format("%0.f",_income),
          ['X-Payroll-Time'] = tostring(m1.Timestamp)
        }
        -- print(tags)
        Send(tags)
      end
      DAO.payroll[pid].supply = _supply
      DAO.payroll[pid].ref = DAO.payroll[pid].ref + 1
      DAO.payroll[pid].least_payrool_time = m1.Timestamp
    end)
  end)
end

DAO.stakeALT = function (quantity,days)
  if not DAO.staking then DAO.staking = {} end
  if not DAO.staking[STAKE_ID] then DAO.staking[STAKE_ID] = {
    staked = 0,
    bal = 0,
    unstaked = 0,
    locked_time = 0,
    ref = 0
  } end
  assert(quantity~=nil and type(quantity)=="number" and quantity>=1 , "type error or missed quantity")
  assert(days~=nil and type(days) == "number", "type error or missed days")
  
  local locked_time = 86400000 * days
  -- assert(type(days)=="number" and locked_time>= math.max(DAO.staking[STAKE_ID].locked_time,86400000*7), "type error or missed days")
  local ref = (DAO.staking[STAKE_ID].ref or 0) + 1
  local tags = {
    Target=AGENT,
    Action="Transfer",
    Quantity = string.format("%0.f",quantity),
    Recipient = STAKE_ID,
    ['X-Transfer-Type'] = "Stake",
    ['X-Locked-Time'] = string.format("%0.f",locked_time),
    ['X-Stake-Ref'] = tostring(ref)
  }
  -- print(tags)
  Handlers.once("once_staked_"..ref,{
    From = STAKE_ID,
    Action = "Staked",
  },function (msg)
    local pid = msg.From
    DAO.staking[pid].staked = DAO.staking[pid].staked + tonumber(msg.Quantity)
    DAO.staking[pid].bal = DAO.staking[pid].bal + tonumber(msg.Quantity)
    DAO.staking[pid].least_stake_time = msg.Timestamp
    DAO.staking[pid].locked_time = math.max(DAO.staking[pid].locked_time,locked_time)
    print("Staked " .. msg.Quantity .. " : "..msg.Id)
  end)
  Send(tags)
end

DAO.getStakingBalance = function()
  Send({
    Target = STAKE_ID,
    Action = "Balance"
  }).onReply(function(msg)
    print(msg.Balance .. " / "..msg.Total.." = "..tonumber(msg.Balance)/tonumber(msg.Total))
    print("________")
    print(string.format("%0.f",tonumber(msg.Total)/0.8 - tonumber(msg.Total)-tonumber(msg.Balance)))
  end)
end

DAO.cliamDividends = function()
  Handlers.once("once_claimed_dividends"..os.time(),{
    From = WUSDC,
    Sender = AGENT,
    Action = "Credit-Notice",
    ['X-Transfer-Type'] = "Distributed",
  },function(msg)
    print("Claimed dividends : "..msg.Quantity )
  end)
  Send({
    Target = AGENT,
    Action = "Claim-Dividends"
  })
end