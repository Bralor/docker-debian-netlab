# Netlab
Tool for the testing of designed BIRD topology and its configuration.

## Installation
### 1. BIRD dependencies installation (distro: debian:latest):
```
sudo apt-get -y update
sudo apt-get -y upgrade
sudo apt-get -y install autoconf \
    build-essential \
    flex \
    bison \
    ncurses-dev \
    libreadline-dev
```

### 2. BIRD installation (from official repository):
```
sudo git clone https://gitlab.labs.nic.cz/labs/bird
cd bird/
sudo autoreconf
sudo ./configure
sudo make
```

### 3. NETLAB installation (from official repository):
```
sudo git clone https://gitlab.labs.nic.cz/labs/bird-tools
sudo cp bird/bird bird/birdc netlab/common/
```

### 4. NETLAB dependencies installation:
```
pip install -r requirements.txt
```

## Usage
Netlab works by default in two different variants.

### 1. Start/stop option
This variant is running through script :start:. Inserting the <test_case> parameter to the "-c" switch runs the selected test case from the :cases: folder.
In this mode it is possible to work with each device individually. Running BIRD for each device with the script :/m<number>/birdc: (for hint, write "?"). To end the current running configuration, run the script :stop:.

Running the scenario with the basic configuration for the OSPF protocol:
```
./start -c cases/cf-ospf-base  
```
Stopping the current running test case:
```
./stop
```

### 2. Runtest option
A variant in which the integration tests will run (see [Test suits](#test-suit)). It is necessary to run with "-m" switch. This flag has two options.

#### 2.1 Save mode
Save the kernel routing tables for selected scenario to :data: folder in the specified test case's folder.

Running the scenario with the basic configuration for the OSPF protocol:
```
./runtest -m save cases/cf-ospf-base
```
Running all the scenarios starting with "cf-ospf":
```
./runtest -m save cases/cf-ospf*
```

#### 2.2 Check mode
It compares the primary kernel routing tables with the current run with the tables from the last SAVE mode. In this mode, the directory: temp: is created at the same time in the root directory where tables from the current run for any differences are stored. If both entries in the tables match, the test passes and the: temp: directory is removed at the end. In the opposite variant, it is possible to check for any differences.

Running the scenario with the basic configuration for the OSPF protocol:
```
./runtest -m check cases/cf-ospf-base
```
Running all the scenarios starting with "cf-ospf":
```
./runtest -m check cases/cf-ospf*
```

## Folder content
Current directory content :netlab:
```
  /netlab
    ├─cases
    | ├─cf-<test_case_1>
    | ├─cf-<test_case_2>
    | ├─cf-<test_case_3>
    | ├─cf-...
    | ...
    ├─common
    | ├─common.start
    | ├─common.stop
    | └─NOTES
    ├─netlab_lib
    ├─runtest
    ├─start
    ├─stop
    └─tests
      ├─base.py
      ├─config.py
      ├─kernel.py
      └─test_doctests.py
```

## Test case
These are predefined configuration files that represent possible situations within the protocol. A list of all test scenarios can be found in the directory: cases :. Each test scenario contains a file: config:, which describes the overall device topology. It also contains configuration files for each device (: bird_m <number> .conf :). The directory also contains a folder :data: where the routing kernel tables are stored in SAVE mode (see [Running "save" mode](#21-save-mode)).

### Variants for the OSPF protocol
#### Topology
```
      ┌─────┐
  M1 -|M3 M5| - M7
  |   |  O  |   |
  M2 -|M4 M6| - M8
      └─────┘
```
#### Description
##### cf-ospf
This is just legacy case. Supports only 4 devices. Topology is also different than the aformentioned. For further details see [cf-ospf-base](#cf-ospf-base).

##### cf-ospf-authentication
OSPFv2: plaintext (M1-M3) --> with mismatched passwords
OSPFv3: HMAC-SHA-1 (M5-M7)
OSPFv2: MD5 (M1-M2)
OSPFv3: HMAC-SHA-256 (M7-M8)
OSPFv2: HMAC-SHA-256 (M2-M4)
OSPFv3: HMAC-SHA-512 (M6-M8) --> with mismatched passwords

##### cf-ospf-base
M3, M4, M5 and M6 are connected with multipoint network (if_net)
M1-M4 --> type PtP
M5-M8 --> type bcast

##### cf-ospf-bfd
This configuration has enabled the BFD support on all connections.

##### cf-ospf-custom
M1-M3; M5-M7 and multipoint --> ttl security
M6-M8 --> set only on the one device
M1-M2; M7-M8 --> real broadcast option (only OSPFv2)
M1-M3; M2-M4 --> link LSA suppression (only OSPFv3)

##### cf-ospf-default
M1,M4,M6,M7 --> have not explicitly set type and interval
M2,M3,M5,M8 --> have default values

##### cf-ospf-nbma
Like the base configuration, but central multipoint network is set as type nbma mode instead of bcast.

##### cf-ospf-net
in progress

##### cf-ospf-priority
Priorities are explicitly set on the central multipoint (M3-10; M5-1; M4-0 and M6-0)

##### cf-ospf-ptmp
Like the base configuration, but central multipoint network is set as type ptmp mode instead of bcast.

#### cf-ospf-vrf
This configuration has three different cycles with single common device named "M1".
```
M9────M8 M7────M6
|      | |      |
|      | |      |
M10─────M1─────M5
       /  \
      /    \
    M2      M4
      \    /
       \  /
        M3
```
1. VRF1: M1, M2, M3, M4
2. VRF2: M1, M5, M6, M7
3. VRF3: M1, M8, M9, M10

### Variants for the BGP protocol
#### Topology
```
       ┌──────────────────────────┐       
       |      M12 ──── M13     AS1|       
       |      /           \       |       
       |     /             \      |       
       |    /               \     |       
       └── M11 ──────────── M14 ──┘       
          /                   \           
 ┌────── M44 ───┐        ┌──── M21 ──────┐ 
 |      /       |        |      \        | 
 |     /        |        |       \       | 
 |    /         |        |        \      | 
 |  M43         |        |        M22    | 
 |   |          |        |         |     | 
 |   |    AS4   |        | AS2     |     | 
 |  M42         |        |        M23    | 
 |     \        |        |        /      | 
 |      \       |        |       /       | 
 |       \      |        |      /        | 
 └────── M41 ───┘        └─── M24 ───────┘ 
           \                 /             
      ┌─── M34 ────────── M31 ───┐        
      |      \            /      |        
      |       \          /       |        
      |        \        /        |        
      |        M33 ── M32     AS3|        
      └──────────────────────────┘        
```

#### Description
##### cf-bgp-base
- AS1: M44 --> M11 (ebgp4, ebgp6),
- AS1: M11, M13, M14 (ibgp4, ibgp6),
- AS1: M12 --> M13 (ospf4, ospf6),
- AS1: M13 --> M14 (ibgp4, ibgp6),
- AS1: M13 --> M21 (ebgp4, ebgp6),
- AS1: M14, M13, M11 (ibgp4, ibgp6),
...

##### cf-bgp-authentication
Configuration settings with parameter "password":
- M14-M21 --> Passwords do not match, eBGPv4("bird1421", "bird1421"),
- M24-M31 --> Passwords match, eBGPv6("xxxx1234", "xxxx1234"),
- M34-M41 --> Passwords match, eBGPv4("borg2345", "borg2345"),
- M44-M11 --> Passwords do not match, eBGPv6("abcd1234", "abcd1234"),

Configuration settings with parameter "ttl security":  # not yet
- M24-M31 --> both devices has ttl security parameter,
- M34-M41 --> only one device has ttl security parameter,


## Test suit
It is a package with specific tests that verify the specific testing case. Each test case has a basic test package (:cases/cf-<test_case>/test-<test_case>.py:). These are basic tests verifying the routing table content. It also contains tests that are individual to each test case.
The test package :cases/cf-<test_case>/test-<test_case>.py: is only a starting file for the tool Pytest. The test function itself is in the file :/tests/kernel.py:. The patch always tests all defined devices.
