local utils = require("modules.utils")
AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT>"


Funds = Funds or {}
Bills = Bills or {}

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

