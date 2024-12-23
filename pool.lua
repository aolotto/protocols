local drive = require("modules.drive")
local utils = require("modules.utils")
local crypto = require(".crypto")
local bint = require('.bint')(256)
local json = require("json")

local initial_state = {
  round = 1,
  bet = {0,0,0}, -- {count, amount, tickets }
  jackpot = 0,
  picks = 0,
  balance = 0,
  players = 0,
  ts_latest_draw = 0,
  ts_latest_bet = 0,
  ts_round_start = tonumber(os.time()),
  ts_round_end = 0,
  run = 1,
  wager_limit = 1000000000,
  minting = {
    quota = {378000000000000000,378000000000000000},
    max_mint = "210000000000000000000",
    minted = "0"
  }
}


AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT>"
-- TOKEN = TOKEN or ao.env.Process.Tags['Token'] or "KCAqEdXfGoWZNhtgPRIL0yGgWlCDUl0gvHu8dnE5EJs"
PRICE = PRICE or 1000000
DIGITS = DIGITS or 3
DRAW_DELAY = DRAW_DELAY or 86400000
JACKPOT_SCALE = JACKPOT_SCALE or 0.5
MIN_CLAIM = MIN_CLAIM or 10
MAX_BET = MAX_BET or 100
TYPE = "3D"
TAXRATE = TAXRATE or 0.4
WAGER_DIFFICULT = WAGER_DIFFICULT or 1.1
DIVDIDEND_LIMIT = DIVDIDEND_LIMIT or 1000000000



Bets = Bets or {}
State = State or utils.deepCopy(initial_state)
Numbers = Numbers or {}
Draws = Draws or {}
Taxation = Taxation or {0,0,0}
Dividends = Dividends or {0,0,0}
Buybacks = Buybacks or {0,0,0}
Participants = Participants or {}



Handlers.add("save-ticket",{
  From = AGENT,
  Action = "Save-Ticket",
  Count = "%d+",
  Amount = "%d+"
},function(msg)
  assert(State.run == 1,"not accept betting at the moment")
  local count = tonumber(msg.Count)
  local amount = tonumber(msg.Amount)
  local tax = tonumber(msg.Tax)

  local x_numbers = msg['X-Numbers']
  if #x_numbers ~= bint.tonumber(DIGITS or 3) then
    x_numbers = utils.getRandomNumber(DIGITS or 3,msg.Id)
  end

  local _player_id = msg.Player
  -- log to participants this round
  if not Participants[_player_id] then
    Participants[_player_id] = {0,0,0}
    utils.increase(State,{players=1})
  end
  utils.increase(Participants[_player_id],{count,amount,1})
  utils.increase(State.bet,{count, amount, 1})
  utils.increase(State,{jackpot = amount * JACKPOT_SCALE, balance = amount})
  utils.update(State,{
    ts_latest_bet = tonumber(msg.Timestamp),
    minting = msg.Data.minting,
  })


  -- update taxation, dividends, buyback
  utils.increase(Taxation,{tax,tax,0})
  utils.increase(Dividends,{tax*0.5,tax*0.5,0})
  utils.increase(Buybacks,{tax*0.5,tax*0.5,0})

  -- Save the bet
  local bet = {
    id = msg['Pushed-For'] or msg.Id,
    round = State.round,
    amount = amount,
    count = count,
    x_numbers = x_numbers,
    created = tonumber(msg.Timestamp),
    player = _player_id,
    price = msg.Price,
    token = msg.Data.token,
    mint = msg.Data.minted,
    sponsor = msg.Data.sponsor
  }
  table.insert(Bets,bet)
  BetsIndexer = BetsIndexer or {}
  BetsIndexer[bet.id] = #Bets

  -- If the total bet amount is less than the maximum of 1000 units of bet amount or jackpot, delay the draw time
  if State.bet[2] < State.wager_limit then
    utils.update(State,{ts_latest_draw = bet.created + DRAW_DELAY})
  end

  -- -- log numbers
  if Numbers[x_numbers] == nil then
    utils.increase(State,{picks=1})
  end
  utils.increase(Numbers,{[x_numbers] = count})

  -- -- send lotto-notice
  local lotto_notice = {
    Target = _player_id,
    Action = "Lotto-Ticket",
    Round = string.format("%.0f", State.round),
    Count = msg.Count,
    Amount = msg.Amount,
    Price = msg.Price,
    Tax = msg.Tax,
    Created = tostring(msg.Timestamp),
    Token = bet.token.id,
    Ticker = bet.token.ticker,
    Denomination = bet.token.denomination,
    Title = "Aolotto Ticket",
    ['Content-Type'] = "text/html",
    ['X-Numbers'] = x_numbers,
    ['Pushed-For'] = bet.id,
    ['X-Sponsor'] = bet.sponsor and table.concat({bet.sponsor.id,bet.sponsor.name,bet.sponsor.url},",") or nil,
    ['X-Mint'] = bet.mint and table.concat({
      bet.mint.amount,
      bet.mint.total,
      bet.mint.unit,
      bet.mint.buff and bet.mint.buff or 0,
      bet.mint.ticker,
      bet.mint.denomination
    },",") or nil,
    Data = string.format([[
      <!DOCTYPE html> 
      <html>
        <head>
          <title>Aolotto Ticket</title>
        </head>
        <body style="background:#DEC9FF;padding:1em; color:black;">
          <h1>Aolotto Ticket</h1>
          <hr/>
          <ul>
            <li>ID: %s</li>
            <li>ROUND: %s</li>
            <li>NUMBER: %s</li>
            <li>AMOUNT: %s</li>
            <li>OWNER: %s</li>
            <li>PAY TOKEN: %s</li>
          </ul>
          <hr/>
          <p><a href="https://aolotto.com">Aolotto</a> - <span>$1 onchain lottery only possible on AO</span><p>
        </body>
      </html>
    ]],bet.id,tostring(bet.round),x_numbers,msg.Count,bet.player,bet.token.id or "-")
  }
  Send(lotto_notice)

  -- check countdown of draw
  if State.ts_latest_draw <= tonumber(msg.Timestamp) then 
    Handlers.archive()
  end

end)


Handlers.add("get",{Action = "Get"},{
  [{Table = "Bets"}] = function(msg)
    msg.reply({
      Total= tostring(#Bets),
      Data= utils.query(Bets,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_created","desc"})
    }) 
  end,
  [{Table = "Draws"}] = function(msg)
    msg.reply({
      Total= tostring(#Draws),
      Data= utils.query(Draws,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_draw","desc"})
    }) 
  end
})

Handlers.add("query",{Action="Query"},{
  [{Table = "Bets",['Query-Id']="_"}] = function(msg)
    local index = BetsIndexer[msg['Query-Id']]
    if index ~= nil then
      msg.reply({Data = Bets[index]})
    end
  end,
  [{Table = "Bets",['Query-Player']="_"}] = function(msg)
    assert(#Bets > 0, "no bets exists")
    local result = utils.filter(function(bet)
      return bet.player == msg['Query-Player']
    end,Bets)
    if #result > 0 then
      msg.reply({
        Total = tostring(#result),
        Data = result
      })
    end
  end,
  [{Table = "Participants",['Query-Player']="_"}] = function (msg)
    msg.reply({Data =Participants[msg['Query-Player']] })
  end
})

Handlers.add("info","Info",function(msg)
  msg.reply({
    ['Name'] = Name,
    ['Token'] = TOKEN,
    ['Agent'] = AGENT,
    ['Tax-Rate'] = tostring(TAXRATE),
    ['Price'] = tostring(PRICE),
    ['Digits'] = tostring(DIGITS),
    ['Draw-Delay'] = tostring(DRAW_DELAY),
    ['Jackpot-Scale'] = tostring(JACKPOT_SCALE),
    ['Min-Claim'] = tostring(MIN_CLAIM),
    ['Max-Bet'] = tostring(MAX_BET),
    ['Pool-Type'] = TYPE,
    ['Dividend-Limit'] = tostring(DIVDIDEND_LIMIT)
  })
end)

Handlers.add("state","State",function(msg)
  msg.reply({ Data=State})
end)



Handlers.add("get",{Action = "Get"},{
  [{Table = "Bets"}] = function(msg)
    msg.reply({
      Total= tostring(#Bets),
      Data= utils.query(Bets,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"created","desc"})
    }) 
  end,
  [{Table = "Draws"}] = function(msg)
    msg.reply({
      Total= tostring(#Draws),
      Data= utils.query(Draws,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_draw","desc"})
    }) 
  end
})



Handlers.add("Cron",function(msg)
  if msg.Timestamp >= State.ts_latest_draw and State.ts_latest_draw > 0 and #Bets > 0 then
    Handlers.archive() -- triger to switch round
  end
  if  Dividends[1] >= DIVDIDEND_LIMIT then
    Handlers.distribute() -- triger to distribute dividends
  end
end)


local function Draw(archive)
  local archive_id = archive.id
  local archived_id = archive.archived_id or ao.id
  local state = archive.state or Archive.state
  local bets = archive.bets or Archive.bets
  local numbers = archive.numbers or Archive.numbers
  local latest_bet = bets[#bets]
  local block = drive.getBlock(archive.block_height or 1520692)
  local seed = block.hash ..'_'..archive_id..'_'..archived_id
  local lucky_number = utils.getDrawNumber(seed,DIGITS or 3)
  local jackpot = state.jackpot

  print("lucky_number:"..lucky_number)

  local matched = numbers[lucky_number] or 0
  local reward_type = matched > 0 and "MATCHED" or "FINAL_BET"
  local tax_rate = TAXRATE
  local taxation = jackpot * tax_rate
  print(jackpot.."-"..taxation.."-"..tax_rate)
  -- filter win bets
  local rewards = {}
  if matched > 0 then
    local _share = jackpot / matched
    for i,bet in ipairs(bets) do
      if bet.x_numbers == lucky_number then
        utils.increase(rewards,{[bet.player]=bet.count * _share})
      end
    end
  else
    rewards[latest_bet.player] = jackpot
  end
  -- count winners
  local winners = 0
  for k,v in pairs(rewards) do winners = winners + 1 end
  -- make draw_notice
  local draw =  {
    round = state.round,
    lucky_number = lucky_number,
    players = state.players,
    jackpot = jackpot,
    rewards = rewards,
    archive = archive_id,
    winners = winners,
    matched = matched,
    reward_type = reward_type,
    created = archive.time_stamp,
    bet = state.bet,
    block_hash = block.hash,
    taxation = taxation,
    tax_rate = tax_rate,
    token = Archive.token,
    archived = archived_id
  }
  local draw_notice = {
    Target = AGENT,
    Action = "Draw-Notice",
    Round = string.format("%.0f", draw.round),
    Players = string.format("%.0f", draw.players),
    Jackpot = string.format("%.0f", draw.jackpot),
    Winners = string.format("%.0f", draw.winners),
    Matched = string.format("%.0f", draw.matched),
    Archive = draw.archive,
    Archived = draw.archived,
    Taxation = tostring(taxation),
    Token = archive.token.id,
    Ticker = archive.token.ticker,
    Denomination = archive.token.denomination,
    Created = tostring(archive.time_stamp or os.time()),
    ['Lucky-Number'] = tostring(draw.lucky_number),
    ['Reward-Type'] = reward_type,
    Bet = table.concat(state.bet,","),
    Data = draw
  }
  Send(draw_notice).onReply(function (msg)
    table.insert(Draws,{round=msg.Round,id=msg['Draw-Id'],archive=msg.Archive, draw_result=msg.Id})
    Archive = nil
    print("Finish drawing for round " .. msg.Round .. " : "..msg.Id)
  end)
end

Handlers.archive = function()
  if not Archive then
    assert(#Bets >=1,"bets length must greater than 1.")
    assert(State.jackpot >= 1,"jackpot must greater than 1.")
    assert(State.ts_latest_draw > 0 and State.ts_latest_draw <= os.time(), "Not yet time for lottery draw")
    State.ts_round_end = os.time()
    Archive = {
      state = utils.deepCopy(State),
      bets = utils.deepCopy(Bets),
      numbers = utils.deepCopy(Numbers),
      participants = utils.deepCopy(Participants)
    }
    Bets = {}
    Numbers = {}
    Participants = {}
    BetsIndexer = {}
    local balance = State.balance - State.jackpot
    local jackpot = balance * JACKPOT_SCALE
    local wager_limit = math.max(State.wager_limit, PRICE * 1000 + jackpot )
    local round = State.round + 1
    utils.update(State,{
      picks = 0,
      bet = {0,0,0},
      players = 0,
      ts_round_start = os.time(),
      ts_latest_bet = 0,
      round = round,
      balance = balance,
      jackpot = jackpot,
      wager_limit = wager_limit,
      ts_round_end = 0,
      ts_latest_draw = 0
    })
    print("Round switch to "..State.round)

    Handlers.once("_once_archive_"..Archive.state.round,{
      From = AGENT,
      Action = "Archived",
      Round = tostring(Archive.state.round)
    },function(m)
      print("The round ["..m.Round.."] has been archived as: "..m['Archive-Id'])
      Archive.id = m['Archive-Id']
      Archive.archived_id = m.Id
      Archive.block_height = m['Block-Height']
      Archive.time_stamp = m.Timestamp
      Archive.token = m.Data.token
      utils.update(State,{minting = m.Data.minting})
      Draw(Archive)
    end)
    Send({
      Target = AGENT,
      Action = "Archive",
      Round = tostring(Archive.state.round),
      Data = Archive.state
    })
  else
    Draw(Archive)
  end
end

Handlers.distribute = function()
  local dividends_bal = Dividends[1]
  assert(dividends_bal>=1,"no dividends to distribute")
  Send({
    Target = AGENT,
    Action = "Distribute-Dividends",
  }).onReply(function (m)
    print("distributed:"..m.Amount.."-"..m.Id)
    Dividends = m.Data
  end)
end

Handlers.add("sync-buybacks",{
  From = function(_from) return _from == AGENT end,
  Action = "Sync-Buybacks"
},function (msg)
  Buybacks = msg.Data.buybacks
end)