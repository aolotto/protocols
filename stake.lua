local utils = require("modules.utils")

AESSET = AESSET or "Cge-oWlgN1b1uWR0pMJQmmJh8rV8F2wApd9ig6bDbbM"
Name = Name or "stakedALT"
Ticker = Ticker or "sALT"
Logo = Logo or "bcwIgXwW2C1OMG8paTtDZtAVPp16cOQlvp3_qnS16eg"
Denomination = Denomination or 6
Balances = Balances or {}
Stakings = Stakings or {}
UnStakings = UnStakings or {}
Stakers = Stakers or {}
Funds = Funds or {}



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
end

Handlers.add("stake",{
  From = AESSET,
  Action = "Credit-Notice",
  ['X-Transfer-Type'] = "Stake",
  Quantity = function (_q)
    return tonumber(_q) >= 1000000000000
  end
},Handlers.stake)

-- Redeem
Handlers.redeem = function (msg)
  print("Redeem")
end

Handlers.add("redeem",{Action="Redeem"},Handlers.redeem)

