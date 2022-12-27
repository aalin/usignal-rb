require "bundler/setup"
require "usignal"

def pause
  sleep 0.1
  puts
end

def title(str)
  pause
  puts "-" * 50
  puts "\e[3m#{str}\e[0m"
end

U = USignal::U

a = U.signal(0)
b = U.signal(0)
c = U.signal(0)

d = U.computed { a.to_i + b }
e = U.computed { b.to_i + c }

dispose = U.effect do
  puts "d: #{d.value}"

  U.effect do
    puts "e: #{e.value}"
  end
end

pause
U.write(b, 2)
pause
puts U.get_signal(d).inspect
pause
U.write(a, 2)
pause
U.write(c, 2)
pause

U.batch do
  U.write(a, 1)
  U.write(b, 3)
  U.write(c, 5)
end

pause

dispose.call
U.write(a, 3)

pause

state = U.rx(
  items: [],
  selected: nil
)

dispose = U.effect do
  puts "Running outer effect #{USignal::Signals::Effect.current.object_id}"

  items = state[:items].map do |item, index|
    puts "Mapping #{item[:id]}"

    selected = U.computed! do
      state[:selected] == item[:id]
    end

    U.on_dispose do
      puts "\e[31mDisposing index #{index}\e[0m"
    end

    U.computed do
      { index:, item: , selected: }
    end
  end

  U.effect do
    puts "\e[33;3mBegin print\e[0m"

    items.map_with_index do |element, i|
      puts "#{element.to_s} #{i}"
    end

    puts "\e[32;3mDone print\e[0m"
  end
end

title "push 1 asd"
state[:items].push(id: 1, title: "asd")

title "set title to hopp"
state[:items].first[:title] = "hopp"

title "pushing item"
state[:items].push(id: 2, title: "asd")

title "batch"

U.batch do
  title "Setting selected to 2"
  state[:selected] = 2
end

U.batch do
  title "Setting selected to 2"
  state[:selected] = 2
end

U.batch do
  title "Setting selected to 3"
  state[:selected] = 3
end

title "Pushing item"
state[:items].push(id: 3, title: state[:items].first[:title])

title "set title to hatt"
state[:items].first[:title] = "hatt"

title "Popping item"
state[:items].pop

title "Shifting item"
puts state[:items].shift.inspect

title "Done"
dispose.call
