# Salud de la base: LumbrasGigabase_OTB_2025.pgn

| Medida | Valor |
|---|---|
| Partidas leídas | 492.184 |
| Tamaño | 496,9 MB |
| Tiempo total | 670,7 s (lectura y validación 602,3 s, duplicados 12,0 s, alias 56,3 s, informe 0,0 s) |
| Memoria máxima (RSS) | 182 MB |
| Hilos | 10 |
| Partidas sin problemas | 490.846 (99,73 %) |
| Saltadas (ilegibles) | 0 |
| Cortadas por jugada ilegal | 2 |

## Validación

| Problema | Gravedad | Partidas | % |
|---|---|---|---|
| Jugada ilegal o ilegible (partida cortada) | error | 2 | 0,00 % |
| Resultado incoherente con el mate final | warning | 116 | 0,02 % |
| Resultado decisivo con ahogado final | warning | 8 | 0,00 % |
| Elo fuera de rango o no numérico | warning | 1214 | 0,25 % |

### Jugada ilegal o ilegible (partida cortada)

- #62623 (byte 67799920) Jammalamadaka, Vihaan – Kaufman, Raymond, 19th Annual SPICE Cup Open, 2025.11.20: 1. d2d4: notación no válida; cortada en 0 medias jugadas
- #62624 (byte 67800638) Harish, Neeraj – Xu, Zhihan (samuel), 19th Annual SPICE Cup Open, 2025.11.20: 1. e2e4: notación no válida; cortada en 0 medias jugadas

### Resultado incoherente con el mate final

- #326 (byte 340226) Musenze Charline – Lakica Elna Mercy, Kireka Open Chess Championship 2025 - Juniors, 2025.12.31: mate de las blancas y resultado 0-1
- #1586 (byte 1683757) Kaziro Jordan – Nanfuma Jesca, Kireka Open Chess Championship 2025 - Juniors, 2025.12.30: mate de las negras y resultado 1-0
- #1617 (byte 1706231) Garikapati Srivalli – Nambohe Jacob, Kireka Open Chess Championship 2025 - Juniors, 2025.12.30: mate de las negras y resultado 1-0
- #1624 (byte 1711418) Kaziro Jordan – Agabangabo Kamugisha, Kireka Open Chess Championship 2025 - Juniors, 2025.12.30: mate de las blancas y resultado 0-1
- #1630 (byte 1715753) Mugabi Ryan – Rumbidzai Ngonzi Birungi, Kireka Open Chess Championship 2025 - Juniors, 2025.12.30: mate de las blancas y resultado 0-1

### Resultado decisivo con ahogado final

- #136418 (byte 145382806) Gomes Barranco, Manuel Ignacio – Garcia Marroquin, Lily Adriana, III Chess Tournament TownCenter SUB14, 2025.09.20: ahogado y resultado 1-0
- #223343 (byte 238561264) Chen, Jiarui – Chen, Siyu(ZJ), 2025 National Amateur Chess Master Tournament Hangzhou Station, 2025.07.26: ahogado y resultado 0-1
- #253265 (byte 270606069) Qian, Youfan – Tang, Jiaze, 2025 China Youth Rapid Championship(U8), 2025.07.05: ahogado y resultado 0-1
- #336082 (byte 357912924) Nurgaliyev, Sauat – Ahmad, Al Khatib, Asian Individual Men's Chess Championships 2025, 2025.05.13: ahogado y resultado 1-0
- #353357 (byte 375817553) Fenton, Sam – Gilmour, Steven G, ?? Muswell Hill FIDE Congress (East Finchley) U2400 - 29th & 30th April 2025, 2025.04.30: ahogado y resultado 0-1

### Elo fuera de rango o no numérico

- #1223 (byte 1285241) Boes, Steffen – Romberg, Lene, Deutsche Vereinsmeisterschaft 2025 U10, 2025.12.30: BlackElo 990
- #1236 (byte 1300463) Giss, Marlene – Bagavathiannan, Pugazh, Deutsche Vereinsmeisterschaft 2025 U10, 2025.12.30: BlackElo 815
- #1237 (byte 1301525) Goecking, Franz – Marschlich, Xenia Erika-Joyce, Deutsche Vereinsmeisterschaft 2025 U10, 2025.12.30: WhiteElo 775
- #1241 (byte 1306208) Gvozdov, Hlib – Schmidt, Ava Helene, Deutsche Vereinsmeisterschaft 2025 U10, 2025.12.30: BlackElo 799
- #1242 (byte 1307206) Hein, Adam Leopold – Todorov, Julian, Deutsche Vereinsmeisterschaft 2025 U10, 2025.12.30: WhiteElo 763

## Duplicados

| Tipo | Partidas a eliminar |
|---|---|
| Exactos | 2429 |
| Subsumidos | 2198 |
| Casi duplicados (posición en la ply 40 o final) | 135 |
| Casi duplicados (MinHash) | 977 |
| **Grupos** | **5628** |

Partidas con firma MinHash: 478.487; pares candidatos LSH verificados: 51.819; cubos LSH descartados por grandes: 0.

### Ejemplo: exact

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1190 | keeper | Boukhris-Ferre, Yacine | Chavez Suarez, Carlos Alberto | Barcelona Christmas IM | 2025.12.30 | 0-1 | 154 |
| 40031 | exact | Boukhris-Ferre, Yacine | Chavez Suarez, Carlos Alberto | Cerrado IM Barcelona Navidad 2025 | 2025.12.?? | 0-1 | 154 |

Propuesta: conservar #1190, eliminar #40031; etiquetas tomadas de otra partida: Event, TimeControl.
- Conflicto en ECO: «B23» / «B06»
- Conflicto en Event: «Cerrado IM Barcelona Navidad 2025» / «Barcelona Christmas IM»
- Conflicto en Round: «8.4» / «8»

### Ejemplo: exact

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1996 | keeper | Juarez Hidalgo, Jimena | Montero Romero, Dany Jose | XLVI Metropolitano Torneo Internacional 2025 Blitz | 2025.12.30 | 0-1 | 110 |
| 2874 | exact | Juarez Hidalgo, Jimena | Montero Romero, Dany Jose | XLVI Metropolitano Torneo Internacional\|Metropolitano Blitz | 2025.12.29 | 0-1 | 110 |

Propuesta: conservar #1996, eliminar #2874; etiquetas tomadas de otra partida: Event.
- Conflicto en Date: «2025.12.30» / «2025.12.29»
- Conflicto en Event: «XLVI Metropolitano Torneo Internacional|Metropolitano Blitz» / «XLVI Metropolitano Torneo Internacional 2025 Blitz»
- Conflicto en Round: «3» / «3.35»

### Ejemplo: exact

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1997 | keeper | Quiros Fernandez, Dereck | Cardenas Vargas, Jean Carlo | XLVI Metropolitano Torneo Internacional 2025 Blitz | 2025.12.30 | 0-1 | 62 |
| 2876 | exact | Quiros Fernandez, Dereck | Cardenas Vargas, Jean Carlo | XLVI Metropolitano Torneo Internacional\|Metropolitano Blitz | 2025.12.29 | 0-1 | 62 |

Propuesta: conservar #1997, eliminar #2876; etiquetas tomadas de otra partida: Event.
- Conflicto en Date: «2025.12.30» / «2025.12.29»
- Conflicto en Event: «XLVI Metropolitano Torneo Internacional|Metropolitano Blitz» / «XLVI Metropolitano Torneo Internacional 2025 Blitz»
- Conflicto en Round: «4» / «4.33»

### Ejemplo: exact

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1998 | keeper | Bonilla Rodriguez, Andres | Hernandez Alvarez, Tania Regla | XLVI Metropolitano Torneo Internacional 2025 Blitz | 2025.12.30 | 1-0 | 133 |
| 2879 | exact | Bonilla Rodriguez, Andres | Hernandez Alvarez, Tania Regla | XLVI Metropolitano Torneo Internacional\|Metropolitano Blitz | 2025.12.29 | 1-0 | 133 |

Propuesta: conservar #1998, eliminar #2879; etiquetas tomadas de otra partida: Event.
- Conflicto en Date: «2025.12.30» / «2025.12.29»
- Conflicto en Event: «XLVI Metropolitano Torneo Internacional|Metropolitano Blitz» / «XLVI Metropolitano Torneo Internacional 2025 Blitz»
- Conflicto en Round: «8» / «8.15»

### Ejemplo: subsumed

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1148 | keeper | Arpith S Bijoy | Burmakin, Vladimir | Athens of the East 5th International Grandmaster Open Chess Tournament \| Cat-A | 2025.12.30 | 1/2-1/2 | 144 |
| 1152 | subsumed | Arpith S Bijoy | Burmakin, Vladimir | Athens of the East 5th International Grandmaster Open Chess tournament (Category | 2025.12.30 | 1/2-1/2 | 143 |

Propuesta: conservar #1148, eliminar #1152; etiquetas tomadas de otra partida: Event, Site, Source, TimeControl.
- Conflicto en Event: «Athens of the East 5th International Grandmaster Open Chess tournament (Category» / «Athens of the East 5th International Grandmaster Open Chess Tournament | Cat-A»
- Conflicto en Round: «9.6» / «9»
- Conflicto en Site: «Amika Hotel,Airport-Mattuthavani Ring Road, Madurai» / «Hotel Amika, Madurai, India»

### Ejemplo: subsumed

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1550 | keeper | Khor, Zhi Chong | Kamarul Azhar, Muhd Haziq Haikal | Johor Chess Festival 2025 \| International Challenger | 2025.12.30 | 1/2-1/2 | 82 |
| 848 | subsumed | Khor, Zhi Chong | Kamarul Azhar, Muhd Haziq Haikal | 10th Johor International Chess Open 2025 - Challenger | 2025.12.30 | 1/2-1/2 | 80 |

Propuesta: conservar #1550, eliminar #848; etiquetas tomadas de otra partida: Event, Source, TimeControl.
- Conflicto en Event: «10th Johor International Chess Open 2025 - Challenger» / «Johor Chess Festival 2025 | International Challenger»
- Conflicto en Round: «7.3» / «7»

### Ejemplo: subsumed

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 2275 | keeper | Prado Lobo, Jonas | Vergara Jofre, Felipe | Cerrado Barcelona Navidad 2025 \| GM 1 | 2025.12.29 | 1/2-1/2 | 38 |
| 2281 | subsumed | Prado Lobo, Jonas | Vergara Jofre, Felipe | Cerrado GM Barcelona Navidad 2025 | 2025.12.29 | 1/2-1/2 | 33 |

Propuesta: conservar #2275, eliminar #2281; etiquetas tomadas de otra partida: Site, Source, TimeControl.
- Conflicto en Event: «Cerrado Barcelona Navidad 2025 | GM 1» / «Cerrado GM Barcelona Navidad 2025»
- Conflicto en Site: «Barcelona ESP» / «Unknown»

### Ejemplo: subsumed

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 2276 | keeper | Moskalenko, Viktor | Cesar Maestre, Bernardo | Cerrado Barcelona Navidad 2025 \| GM 2 | 2025.12.29 | 1/2-1/2 | 83 |
| 2284 | subsumed | Moskalenko, Viktor | Cesar Maestre, Bernardo | Cerrado GM2 Barcelona Navidad 2025 | 2025.12.29 | 1/2-1/2 | 82 |

Propuesta: conservar #2276, eliminar #2284; etiquetas tomadas de otra partida: Site, Source, TimeControl.
- Conflicto en Event: «Cerrado Barcelona Navidad 2025 | GM 2» / «Cerrado GM2 Barcelona Navidad 2025»
- Conflicto en Round: «7.2» / «7»
- Conflicto en Site: «Barcelona» / «Unknown»

### Ejemplo: near-positionAtPly

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 2538 | keeper | Biriya, Mohammadamin | Vijay, Rege | Johor Chess Festival 2025 \| International Open | 2025.12.29 | 1/2-1/2 | 74 |
| 2052 | near (positionAtPly) | Biriya, Mohammadamin | Vijay, Rege | 10th Johor International Chess Open 2025 | 2025.12.29 | 1/2-1/2 | 72 |

Propuesta: conservar #2538, eliminar #2052; etiquetas tomadas de otra partida: Site, Source, TimeControl.
- Conflicto en Event: «Johor Chess Festival 2025 | International Open» / «10th Johor International Chess Open 2025»
- Conflicto en Round: «1» / «5»
- Conflicto en Site: «Main hall, Fairview International School» / «Unknown»

### Ejemplo: near-positionAtPly

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 6473 | keeper | Linsangan, Raymond | Zhang, Hanwen | Hong Kong International Open 2025 - Challengers | 2025.12.26 | 0-1 | 74 |
| 6536 | near (positionAtPly) | Linsangan, Raymond | Zhang, Hanwen | Hong Kong International Open Chess Championship 2025 \| Challengers | 2025.12.26 | 0-1 | 70 |

Propuesta: conservar #6473, eliminar #6536; etiquetas tomadas de otra partida: Event.
- Conflicto en Event: «Hong Kong International Open Chess Championship 2025 | Challengers» / «Hong Kong International Open 2025 - Challengers»
- Conflicto en Round: «6» / «6.16»
- Conflicto en Site: «Queen Elizabeth Stadium in Wanchai, Hong Kong.» / «Wan Chai Stadium»

### Ejemplo: near-positionAtPly

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 6491 | keeper | Tong, Ka Yau Caspar | Turmunkh Avirsed | Hong Kong International Open 2025 - Challengers | 2025.12.26 | 1-0 | 55 |
| 6539 | near (positionAtPly) | Tong, Ka Yau Caspar | Turmunkh Avirsed | Hong Kong International Open Chess Championship 2025 \| Challengers | 2025.12.26 | 1-0 | 55 |

Propuesta: conservar #6491, eliminar #6539; etiquetas tomadas de otra partida: Event.
- Conflicto en Event: «Hong Kong International Open Chess Championship 2025 | Challengers» / «Hong Kong International Open 2025 - Challengers»
- Conflicto en Round: «6» / «6.37»
- Conflicto en Site: «Queen Elizabeth Stadium in Wanchai, Hong Kong.» / «Wan Chai Stadium»

### Ejemplo: near-positionAtPly

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 10185 | keeper | Karthik Rajaa | Peng, Hongchi | 17th Penang Heritage City International Chess Open 2025 (Open) | 2025.12.21 | 0-1 | 50 |
| 10235 | near (positionAtPly) | Karthik Rajaa | Peng, Hongchi | 17th Penang Heritage City International Chess Open 2025 (Open) | 2025.12.21 | 0-1 | 48 |

Propuesta: conservar #10185, eliminar #10235; etiquetas tomadas de otra partida: Site, Source, TimeControl.
- Conflicto en ECO: «A20» / «A00»
- Conflicto en Round: «6.5» / «6»
- Conflicto en Site: «Wesley Methodist School, Penang (International)» / «Unknown»

### Ejemplo: near-minHash

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 1149 | keeper | Advik Amit Agrawal | Tologon tegin, Semetei | Athens of the East 5th International Grandmaster Open Chess Tournament \| Cat-A | 2025.12.30 | 1/2-1/2 | 131 |
| 1009 | near (minHash) | Advik Amit Agrawal | Tologontegin, S | 5th Athens of the East Op | 2025.12.30 | 1/2-1/2 | 131 |

Propuesta: conservar #1149, eliminar #1009; etiquetas tomadas de otra partida: Source.
- Conflicto en Black: «Tologon tegin, Semetei» / «Tologontegin, S»
- Conflicto en Event: «Athens of the East 5th International Grandmaster Open Chess Tournament | Cat-A» / «5th Athens of the East Op»
- Conflicto en Round: «9.12» / «9.13»
- Conflicto en WhiteElo: «2116» / «2118»

### Ejemplo: near-minHash

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 3344 | keeper | Balkishan, A | Tologon tegin, Semetei | Athens of the East 5th International Grandmaster Open Chess tournament (Category | 2025.12.28 | 0-1 | 106 |
| 3337 | near (minHash) | Balkishan, A | Tologontegin, S | 5th Athens of the East Op | 2025.12.28 | 0-1 | 106 |

Propuesta: conservar #3344, eliminar #3337; etiquetas tomadas de otra partida: ECO.
- Conflicto en Black: «Tologon tegin, Semetei» / «Tologontegin, S»
- Conflicto en Event: «Athens of the East 5th International Grandmaster Open Chess tournament (Category» / «5th Athens of the East Op»
- Conflicto en Round: «7» / «7.11»
- Conflicto en Site: «Amika Hotel,Airport-Mattuthavani Ring Road, Madurai» / «Madurai IND»

### Ejemplo: near-minHash

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 3381 | keeper | Citak, Selim | Fernandes Barbosa Dos Santos, Gabriel | BASEL XMAS FESTIVAL 2025- MASTER | 2025.12.28 | 1/2-1/2 | 31 |
| 3402 | near (minHash) | Citak, Selim | Fernandes Barbosa Dos Santos, Gabriel | Basel Christmas Open 2025 | 2025.12.28 | 1/2-1/2 | 31 |

Propuesta: conservar #3381, eliminar #3402; etiquetas tomadas de otra partida: ECO.
- Conflicto en Event: «BASEL XMAS FESTIVAL 2025- MASTER» / «Basel Christmas Open 2025»
- Conflicto en Round: «4» / «4.7»
- Conflicto en Site: «Moevenpick Hotel - Aeschengraben 25 - CH-4051 Basel» / «Basel SUI»

### Ejemplo: near-minHash

| # | Relación | Blancas | Negras | Evento | Fecha | Resultado | PlyCount |
|---|---|---|---|---|---|---|---|
| 3476 | keeper | Francisco Javier Perez Castro | Perez, Camacho Julio Emmanuel | Copa Toluca 2025 | 2025.12.28 | 0-1 | 84 |
| 3421 | near (minHash) | Perez Castro, Francisco Javier | Perez Camacho, Julio Emmanuel | COPA TOLUCA DE AJEDREZ GRUPO C | 2025.12.28 | 0-1 | 84 |

Propuesta: conservar #3476, eliminar #3421; etiquetas tomadas de otra partida: Event, Site, Source, TimeControl.
- Conflicto en Black: «Perez, Camacho Julio Emmanuel» / «Perez Camacho, Julio Emmanuel»
- Conflicto en Round: «9.11» / «9»
- Conflicto en Site: «Toluca de Lerdo, Mexico» / «Unknown»

## Jugadores

Grafías distintas: 86.332.

| Confianza | Propuestas de alias |
|---|---|
| certain | 0 |
| likely | 1273 |
| possible | 3639 |

| Confianza | Canónica | Alias | Motivos |
|---|---|---|---|
| likely | Aabling-Thomsen, Jakob (14, FIDE 1407589, 2327–2340) | Aabling Thomsen, J (1, 2335–2335) | similitud 1.00; Elo compatible (2327–2340 / 2335–2335); años activos compatibles; inicial frente a nombre completo; FIDE ID solo en una grafía |
| likely | Aayan, Gupta (2, 1588–1718) | Aayan Gupta (1, 1597–1597) | similitud 1.00; Elo compatible (1588–1718 / 1597–1597); años activos compatibles; mismos nombres en otro orden |
| likely | Abel, Dennes (11, FIDE 24605417, 2367–2383) | Abel, D (3, 2383–2411) | similitud 1.00; Elo compatible (2367–2383 / 2383–2411); años activos compatibles; inicial frente a nombre completo; FIDE ID solo en una grafía |
| likely | Abhinav, Anand (5, 1922–1929) | Abhinav Anand (3, 1929–1952) | similitud 1.00; Elo compatible (1929–1952 / 1922–1929); años activos compatibles; mismos nombres en otro orden |
| likely | Abhyuday, Santhosh (9, FIDE 25624849, 1953–2094) | Santhosh, Abhyuday (6, 1953–1953) | similitud 1.00; Elo compatible (1953–1953 / 1953–2094); años activos compatibles; mismos nombres en otro orden; FIDE ID solo en una grafía |
| likely | Aczel, Gergely (167, FIDE 727709, 2417–2496) | Aczel, G (2, 2435–2456) | similitud 1.00; Elo compatible (2417–2496 / 2435–2456); años activos compatibles; inicial frente a nombre completo; FIDE ID solo en una grafía |
| likely | Adhiban, B (84, FIDE 5018471, 2509–2557) | Adhiban, Baskaran (35, 2518–2557) | similitud 1.00; Elo compatible (2518–2557 / 2509–2557); años activos compatibles; inicial frente a nombre completo; FIDE ID solo en una grafía |
| likely | Sathvik Adiga (60, FIDE 25745700, 2341–2396) | Sathvik, Adiga (17, 2341–2370) | similitud 1.00; Elo compatible (2341–2396 / 2341–2370); años activos compatibles; mismos nombres en otro orden; FIDE ID solo en una grafía |
| possible | Aakash G (80, FIDE 25644394, 2100–2373) | Akash, Gupta (3) | similitud 1.00; años activos compatibles; misma transliteración del apellido; inicial frente a nombre completo; FIDE ID solo en una grafía |
| possible | Aaryansh (2, FIDE 88177971, 1484–1484) | Aryansh (5) | similitud 1.00; años activos compatibles; misma transliteración del apellido; FIDE ID solo en una grafía |
| possible | Abad Salazar, Cesar Enrique (9, FIDE 144458800, 1743–1743) | Cesar Enrique Abad Salazar (1) | similitud 1.00; años activos compatibles; mismos nombres en otro orden; FIDE ID solo en una grafía |
| possible | Abdukhakimov, Akbarali (99, FIDE 14219522, 2217–2363) | Abduhakimov, Akbarali (5) | similitud 1.00; años activos compatibles; misma transliteración del apellido; FIDE ID solo en una grafía |
| possible | Abdulkhamidov, Abdumajid (2, FIDE 14236753, 1533–1533) | Abdulhamidov, Abdumajid (9) | similitud 1.00; años activos compatibles; misma transliteración del apellido; FIDE ID solo en una grafía |
| possible | Abhigyan, Das (3, 1632–1632) | Abhigyan Das (2, 1787–1787) | similitud 1.00; años activos compatibles; mismos nombres en otro orden |
| possible | Abhishek, Das (2, FIDE 5013348, 2226–2226) | Abhishek, D (2) | similitud 1.00; años activos compatibles; inicial frente a nombre completo; FIDE ID solo en una grafía |
| possible | Abu, Hanif (33, FIDE 10206647, 1878–1878) | Abu Hanif (2, 2109–2109) | similitud 1.00; años activos compatibles; mismos nombres en otro orden; FIDE ID solo en una grafía |
