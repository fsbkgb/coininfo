configure do
  Mongoid.load!("config/mongoid.yml", :development)
  set :server, 'thin'
  set :static, true
  set :root, File.dirname(__FILE__)
  set :public_dir, 'public'
end

class Block
  include Mongoid::Document
  field :height, type: Integer
  field :blockhash, type: String
  field :size, type: String
  field :version, type: String
  field :merkleroot, type: String
  field :tx, type: Array
  field :nonce, type: String
  field :bits, type: String
  field :difficulty, type: String
  field :previousblockhash, type: String
  field :nextblockhash, type: String
  field :time, type: String
  field :retarget, type: Boolean, default: false
  index({ height: 1 })
end

@@coin = "2CHcoin"
@daemon = "./2chcoind"
@ch_diff = 240
@ch_reward = 30240
@first_reward = 16384
@max_money = 5000000000
@block_time = 60
update_interval = "1m"


scheduler = Rufus::Scheduler.new(:max_work_threads => 1)

scheduler.every update_interval do

  def total_coin(height)
    reward, interval = @first_reward, @ch_reward
    total_btc = reward
    reward_era, remainder = (height).divmod(interval)
    reward_era.times{
      total_btc += interval * reward
    reward = (reward / 2).ceil
    }
    total_btc += remainder * reward
    return total_btc
  end
  
  def read_block (y)
    blocknumber = y.to_s
    blockhash = `#{@daemon} getblockhash #{blocknumber}`
    blck = `#{@daemon} getblock #{blockhash}`
    parsedblock = JSON.parse(blck)
    retarget = true if y.to_i % @ch_diff == 0
    @block = Block.new(height: (parsedblock["height"]).to_i,
                       blockhash: parsedblock["hash"],
                       size: parsedblock["size"],
                       version: parsedblock["version"],
                       merkleroot: parsedblock["merkleroot"],
                       tx: parsedblock["tx"],
                       time: parsedblock["time"],
                       nonce: parsedblock["nonce"],
                       bits: parsedblock["bits"],
                       difficulty: parsedblock["difficulty"],
                       previousblockhash: parsedblock["previousblockhash"],
                       nextblockhash: parsedblock["nextblockhash"],
                       retarget: retarget)
    @block.save
  end 
  
  def draw_diff (blocks)
    diff = []
    date = []
    
    blocks.reverse.each do |b|
      diff.push(b.difficulty.to_f)
      date.push(Time.at(b.time.to_i).utc)
    end
    
    p = Rdata.new
    p.add_point(diff,"Serie1")
    p.add_point(date,"Serie2");
    p.add_all_series()
    
    p.remove_serie("Serie2")
    p.set_abscise_label_serie("Serie2")
    ch = Rchart.new(627,400)
    ch.set_graph_area(120,30,600,275)
    ch.draw_filled_rectangle(0,0,627,400,238,238,238)
    ch.draw_rounded_rectangle(5,5,622,395,5,204,204,204)
    ch.draw_graph_area(255,255,255,true)
    ch.draw_scale(p.get_data,p.get_data_description,Rchart::SCALE_START0,150,150,150,true,45,1,false,2,false)
    ch.draw_grid(4,true,230,230,230,50)
    ch.draw_treshold(0,143,55,72,true,true)

    ch.draw_filled_line_graph(p.get_data,p.get_data_description,30)
    ch.render_png("public/diff.png")
  end
  
  def draw_mined (mined)
    unmined = @max_money - mined
    p = Rdata.new
    p.add_point([unmined,mined],"Serie1")
    p.add_point(["Unmined #{unmined} coins","Mined #{mined} coins"],"Serie2")
    p.add_all_series
    p.set_abscise_label_serie("Serie2")
    ch = Rchart.new(627,400)
    ch.draw_filled_rectangle(0,0,627,400,238,238,238)
    ch.draw_rounded_rectangle(5,5,622,395,5,204,204,204)
    ch.create_color_gradient_palette(195,204,56,223,110,41,5)
    ch.antialias_quality=0
    ch.draw_pie_graph(p.get_data,p.get_data_description,310,200,150,Rchart::PIE_PERCENTAGE_LABEL,false,50,20,5)
    ch.render_png("public/mined.png")
  end

  def do_index
    @@blocks = Block.desc(:height).limit(101)
    count = @@blocks.count(true)
    retargets = Block.desc(:height).limit(25).where(retarget: true)
    last_retarget = retargets.first
    last_block = @@blocks[0].height.to_i
    @@next_retarget = last_retarget.height.to_i + @ch_diff - last_block - 1
    t = Time.now.to_i - last_retarget.time.to_i
    n = last_block - last_retarget.height.to_i+1
    @@next_diff = (@@blocks[0].difficulty.to_f * @block_time * n / t).round(3)
    mined = total_coin(@@blocks[0].height)
    @@block_reward = @first_reward / (2 ** (last_block / @ch_reward.to_f).floor)
    @@next_reward = @ch_reward - last_block.remainder(@ch_reward) - 1
    draw_diff (retargets)
    draw_mined (mined)
    template = File.read('views/index.haml')
    haml_engine = Haml::Engine.new(template)
    html_page = File.new('public/index.html', "w")
    html_page.write(haml_engine.render)
    html_page.close
  end
  
  blockcount = (`#{@daemon} getblockcount`).to_i
  if blockcount > 1
    if Block.all.size == 0
      blockcount.times do |y|
        read_block (y)
      end
    else
      Block.last.destroy
      last_block_height = Block.last.height.to_i + 1
      last_block_height.upto(blockcount) do |y|
        read_block (y)
      end
    end
    do_index
  end
end

get '/' do
  send_file File.join('public', 'index.html')
end
