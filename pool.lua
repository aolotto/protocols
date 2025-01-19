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
DRAW_DIFF_BLOCKHEIGHT = DRAW_DIFF_BLOCKHEIGHT or 5
MINTING_PLUS_DUR = MINTING_PLUS_DUR or 600000
MINTING_PLUS_LOCKER = MINTING_PLUS_LOCKER or false



Bets = Bets or {}
State = State or utils.deepCopy(initial_state)
Numbers = Numbers or {}
Draws = Draws or {}
Taxation = Taxation or {0,0,0}
Dividends = Dividends or {0,0,0}
Buybacks = Buybacks or {0,0,0}
Participants = Participants or {}
GapRewards = GapRewards or {}



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
    mint_speed = msg['Mint-Speed'] or State.mint_speed
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
    sponsor = msg.Data.sponsor,
    note = msg.Note or nil
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
    Note = msg.Note,
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
          <div>%s</div>
          <hr/>
          <p><a href="https://aolotto.com">Aolotto</a> - <span>$1 onchain lottery only possible on AO</span><p>
        </body>
      </html>
    ]],bet.id,tostring(bet.round),x_numbers,msg.Count,bet.player,bet.token.id or "-", bet.note or "")
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
  local _state = utils.deepCopy(State)
  _state.picks = Numbers
  msg.reply({ Data=_state})
end)


Handlers.add("gap_rewards","Gap-Rewards",function(msg)
  msg.reply({ Data=GapRewards})
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
  print("cron")
  if msg.Timestamp >= State.ts_latest_draw and State.ts_latest_draw > 0 and #Bets > 0 then
    Handlers.archive() -- triger to switch round
  end
  if Dividends[1] >= DIVDIDEND_LIMIT then
    Handlers.distribute() -- triger to distribute dividends
  end
  -- triger to draw
  if Archive and Archive.id and Archive.archived_id and Archive.block_height then
    if msg['Block-Height'] - Archive.block_height >= DRAW_DIFF_BLOCKHEIGHT then
      Archive.drawing = true
      Archive.draw_time = msg.Timestamp
      Archive.draw_height = msg['Block-Height']
      Handlers.draw(Archive) -- triger to distribute dividends
    end
  end
  if msg.Timestamp - math.max(State.ts_latest_bet,State.latest_minting_plus) >= MINTING_PLUS_DUR and #Bets > 0 and State.ts_round_start>0 and MINTING_PLUS_LOCKER==false then
    local mint_time = math.max(State.ts_latest_bet,State.latest_minting_plus)+MINTING_PLUS_DUR
    print("Minting plus triger ->"..msg.Timestamp.."/"..mint_time.."-> diff:".. msg.Timestamp - mint_time)
    Handlers.mintingPlus(mint_time)
  end
end)


Handlers.draw = function(archive)
  local draw_time = archive.draw_time or os.time()
  local archive_id = archive.id
  local archived_id = archive.archived_id or ao.id
  local state = archive.state or Archive.state
  local bets = archive.bets or Archive.bets
  local numbers = archive.numbers or Archive.numbers
  local latest_bet = bets[#bets]
  local block = drive.getBlock(archive.block_height+DRAW_DIFF_BLOCKHEIGHT or archive.draw_height or 1581160)
  local seed = block.indep_hash ..'_'..archive_id..'_'..archived_id.."_"..latest_bet.id.."_"..tostring(draw_time)
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
    block_hash = block.indep_hash,
    taxation = taxation,
    tax_rate = tax_rate,
    token = Archive.token,
    archived = archived_id,
    latest_bet_id = latest_bet.id,
    seed = seed,
    draw_height = block.height,
    draw_time = draw_time
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
    Created = tostring(draw_time or os.time()),
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
    GapRewards = {}
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
      ts_latest_draw = 0,
      latest_minting_plus = 0,
      minting_plus = {0,0}
    })
    print("Round switch to "..State.round)
  end
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
    -- Draw(Archive)
  end)
  Send({
    Target = AGENT,
    Action = "Archive",
    Round = tostring(Archive.state.round),
    Data = Archive.state
  })
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


Handlers.add("numbers","Numbers",function(msg)
  msg.reply({Data=Numbers})
end)


Handlers.mintingPlus = function (timestamp)
  if State.minting.quota[1] > 0 then
    MINTING_PLUS_LOCKER = true
    State.latest_minting_plus = timestamp

    if not State.minting_plus then
      State.minting_plus = {0,0}
    end
    
    local lastest_bet = Bets[#Bets]

    local message = {
      Target = AGENT,
      Action = "Minting-Plus",
      Player = lastest_bet.player,
      ["Bet-Id"] = lastest_bet.id,
      ["Bet-Index"] = tostring(#Bets),
      ["Mint-Time"] = tostring(timestamp)
    }
    print("distribute gap-reward")
    Send(message).onReply(function (msg)
      MINTING_PLUS_LOCKER = false
      local minted = msg.Data.minted
      -- log gap-rewards
      if not GapRewards then GapRewards = {} end
      if not GapRewards[msg['Bet-Id']] then GapRewards[msg['Bet-Id']] = {} end
      table.insert(GapRewards[msg['Bet-Id']],{msg["Mint-Time"],minted.total,msg.Id})

      -- update state
      utils.update(State,{
        minting = msg.Data.minting
      })
      utils.increase(State.minting_plus,{minted.total,1})
      
      -- update the bet
      local index = tonumber(msg['Bet-Index']) or BetsIndexer[msg['Bet-Id']]
      if minted then
        if not Bets[index].mint.plus then
          Bets[index].mint.plus = {0,0} -- {total, counts}
        end
        utils.increase(Bets[index].mint.plus,{minted.total,1})
        -- print("Minting plus for bet "..msg['Bet-Id'].." - at "..msg.Timestamp)
      end
    end)
  end
end