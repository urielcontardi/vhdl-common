=====================
VHDL Common Library
=====================

Overview
========

This repository contains a collection of reusable VHDL components designed for general purposes. The components are organized into modular packages that can be easily integrated into larger FPGA-based systems.

Repository Structure
===================

.. code-block:: text

   common/
   ├── doc/                     # Documentation files
   ├── modules/                 # VHDL component modules
   │   ├── bilinear_solver/     # Bilinear state-space solver (DSP48E1 multiply pipeline)
   │   ├── blinky/              # LED blinker
   │   ├── clarke_transform/    # abc -> alpha/beta (Clarke) transform
   │   ├── debouncer/           # Input debouncer
   │   ├── edge_detector/       # Rising/falling edge detector
   │   ├── fifo/                # Async/sync FIFO
   │   ├── linear_solver/       # Linear state-space solver
   │   ├── npc_modulator/       # 3-level NPC PWM modulator + gate driver
   │   └── uart/                # UART TX/RX with FIFOs
   └── README.rst

Authors
=======

- **Uriel Abe Contardi** (urielcontardi@hotmail.com)
- **Vinícius de Carvalho Monteiro Longo** (longo.vinicius@gmail.com)
