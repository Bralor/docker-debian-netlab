# Chování BIRD socketů

## Požadavky

### Kombinace
- Sockety
   -UDP
   - Raw 
- IP
   - IPv4
   - IPv6
- Způsob vysílání
   - Unicast
   - Multicast (224.0.0.9)
   - Directed broadcast podle masky sítě
   - Universal broadcast (255.255.255.255)

### Vlastnosti

- Na straně odesílání
    - Odesila na spravne rozhrani, ackoli routovaci tabulka je jina, ale cilova adresa je dostupna na dane siti
    - Na odesilacim rozhrani je vice adres
    - Odesila se spravnou nastavenou zdrojovou adresou, ktera nemusi byt na danem rozhrani, ale musi byt alespon na nekterem jinem rozhrani
    - Overit, ze packety maji cilovou adresu takovou, kterou ocekavame
   
- Na straně přijímání
    - Nemelo by prijmout packet z jineho rozhrani nez je nastaveny
    - Precist source-addr a local iface


## Testcase

### Nastavení
- Interface s prefixem /24
    - 2 IP adresy na interface
- Odstranene smerovani v routovaci tabulce (ping nefunguje)

#### Odesílání
- Jako lokální adresa se použije adresa jiného lokálního zařízení (`gr????`)
- Po otevření socketu se nastaví TTL na 3

#### Přijímání

1. Nastaví se na *správný* interface
2. Nastaví se na *jiný* interface (nemělo by nic přijmout)

### Ukázky (IPv4, raw socket)

#### Unicast
     ./rcv -i lnk111
     ./snd -c 10 -i lnk111 -t 3 -l 192.168.214.188 10.210.1.51

#### Multicast
     ./rcv -i lnk111 -m 224.0.0.9
     ./snd -c 10 -i lnk111 -t 3 -l 192.168.214.188 224.0.0.9

#### Directed Broadcast 
     ./rcv -i lnk111 -b
     ./snd -c 10 -i lnk111 -t 3 -l 192.168.214.188 -b 10.210.1.255

#### Universal Broadcast
     ./rcv -i lnk111 -b
     ./snd -c 10 -i lnk111 -t 3 -l 192.168.214.188 -b 255.255.255.255

### Kontrola
- `tcpdump -i lnk??? -vvvn`
    - Správný interface
    - Správná IP na obou koncích

#### Přijímání
1. 
    - Přijmutí
    - Taková IP odesílatele, kterou jsme nastavili
    - Správně rozpoznané rozhraní, na kterém jsme packet přijmuli
    - Správná hodnota TTL
2.
    - Nepřijme nic

## Výsledky

### Linux

|              |   Unicast   |  Multicast  | Directed Broadcast | Universal Broadcast |  
|:------------:|:-----------:|:-----------:|:------------------:|:-------------------:|
| **IPv4 UDP** |             |             |                    |
| **IPv4 Raw** |             |             |                    |
| **IPv6 UDP** |             |             |                    |
| **IPv6 Raw** |             |             |                    |


<table>
  <tr>
    <th colspan=2></td><th>Unicast</td><th>Multicast</td><th>Broadcast</td>
  </tr>

  <tr>
    <th rowspan=2> IPv4 </th><th>UDP</th><td>?</td><td>?</td><td>?</td>
  </tr>
  <tr>
    <th>Raw</th><td>?</td><td>Změna TTL nefunguje po nastavení socketu na multicast</td><td>?</td>
  </tr>

  <tr>
    <th rowspan=2> IPv6 </th><th>UDP</th><td>?</td><td>?</td><td>?</td>
  </tr>
  <tr>
    <th>Raw</th><td>?</td><td>?</td><td>?</td>
  </tr>
</table>

### FreeBSD

|              |   Unicast   |  Multicast  | Directed Broadcast | Universal Broadcast |  
|:------------:|:-----------:|:-----------:|:------------------:|:-------------------:|
| **IPv4 UDP** |             |             |                    |
| **IPv4 Raw** |             |             |                    |
| **IPv6 UDP** |             |             |                    |
| **IPv6 Raw** |             |             |                    |


### OpenBSD

|              |   Unicast   |  Multicast  | Directed Broadcast | Universal Broadcast |  
|:------------:|:-----------:|:-----------:|:------------------:|:-------------------:|
| **IPv4 UDP** |             |             |                    |
| **IPv4 Raw** |             |             |                    |
| **IPv6 UDP** |             |             |                    |
| **IPv6 Raw** |             |             |                    |


### NetBSD

|              |   Unicast   |  Multicast  | Directed Broadcast | Universal Broadcast |  
|:------------:|:-----------:|:-----------:|:------------------:|:-------------------:|
| **IPv4 UDP** |             |             |                    |
| **IPv4 Raw** |             |             |                    |
| **IPv6 UDP** |             |             |                    |
| **IPv6 Raw** |             |             |                    |

