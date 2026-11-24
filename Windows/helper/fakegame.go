// fakegame — пустая программа для Embers: ничего не делает и спит.
// Embers копирует её по пути, который совпадает с именем игры в базе Discord.
// Сборка: GOOS=windows GOARCH=amd64 go build -ldflags "-H=windowsgui -s -w" -o fakegame.exe fakegame.go
package main

import "time"

func main() {
	for {
		time.Sleep(time.Hour)
	}
}
