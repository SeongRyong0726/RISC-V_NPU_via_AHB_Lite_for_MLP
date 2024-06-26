`timescale 100ns/1ns
module fsm_copy #(
//assume : .ARRAY_M = ARRAY_N
    parameter integer NUM_VAR = 4,
    

    parameter integer ARRAY_N = 8,
    parameter integer ARRAY_M = 8,

    parameter integer ACT_WIDTH = 8,
    parameter integer WGT_WIDTH = 8,
    parameter integer PE_OUT_WIDTH = 32,

    parameter integer RAM_SIZE = 1024,
    parameter integer ADDR_WIDTH = $clog2(RAM_SIZE),
    
    parameter integer DEPTH = 8,
    parameter integer DATA_WIDTH = 32,
    parameter integer OUT_WIDTH = 32
    
    

) ( 
    input wire clk,

    
        //special purpose BRAM
    output reg [32-1:0]         addr_sp_bram,
    output reg                  enable_sp_bram,
    input wire [32-1:0]          data_out_sp_bram,
    output reg [4-1 :0]         w_enable_sp_bram,
    output reg [32-1:0]         data_in_sp_bram,
        //A_BRAM
    output reg [32-1:0]         addr_a_bram,
    output reg                  enable_a_bram,
    output reg [ARRAY_N-1:0]    bram_to_a_ram_w_en,
        //W_BRAM
    output reg [32-1:0]         addr_w_bram,
    output reg                  enable_w_bram,
    output reg [ARRAY_M-1:0]    bram_to_w_ram_w_en,
        //O_BRAM
    output reg [32-1:0]         addr_o_bram,
    output reg                  enable_o_bram,
    output reg [4-1 :0]         w_enable_o_bram,


    output reg                          system_reset,
    //A buf
    output reg                          a_buf_on,
    output reg [ADDR_WIDTH-1:0]         a_base_addr,
    output reg [$clog2(ARRAY_N) : 0]    a_num_rows,
    //W_buf
    output reg                          mode,
    output reg                          w_buf_on,
    output reg [ADDR_WIDTH -1:0]        w_base_addr,
    output reg [$clog2(ARRAY_N):0]      w_num_cols, 
    //systolic array
    output reg [2:0]                    operation_signal_in,

    //O_buffer
    output reg                          o_idx_gen_on,
    output reg                          o_ag_o_on,
    output reg                          o_drain,
    output reg [ADDR_WIDTH -1 : 0]      o_base_addr,
    output reg [$clog2(ARRAY_M)-1:0]    o_ram_idx,
    output reg [ADDR_WIDTH-1 : 0]       o_read_addr,
    
    output wire [5:0]                   DEBUG_state,
    output wire [31:0]                  DEBUG_matmul_var_1,
    output wire [31:0]                  DEBUG_matmul_var_2,
    output wire [31:0]                  DEBUG_matmul_var_3,
    output wire [31:0]                  DEBUG_matmul_var_4
);
    // =========== STATES =============
    parameter [5:0] IDLE = 6'b111111;
    parameter [5:0] GET_VAR_R_REQ = 6'b000001; //01
    parameter [5:0] GET_VAR_W_REG = 6'b000010; //02
    parameter [5:0] DECIDE_MODE = 6'b000011;    //03
    parameter [5:0] UPDATE_COUNT = 6'b000100;   //04

    parameter [5:0] FILL_RAM_WS = 6'b010000;    //10
    parameter [5:0] W_LOAD = 6'b010001;         //11
    parameter [5:0] A_FLOW_1 = 6'b010010;       //12
    parameter [5:0] A_FLOW_2 = 6'b010011;       //13
    parameter [5:0] A_FLOW_3 = 6'b010100;       //14
    parameter [5:0] STORE_AT_RAM_WS = 6'b010101;//15
    parameter [5:0] WAIT_DELAY_WS = 6'b010110; //16
    
 
    parameter [5:0] FILL_RAM_OS = 6'b100000;        //20
    parameter [5:0] OS_FLOW_1 = 6'b100001;          //21
    parameter [5:0] OS_FLOW_2 = 6'b100010;          //22
    parameter [5:0] STORE_AT_RAM_OS_1 = 6'b100011;  //23 
    parameter [5:0] STORE_AT_RAM_OS_2 = 6'b100100;  //24
    parameter [5:0] STORE_AT_RAM_OS_EDGE = 6'b100101; //25
    parameter [5:0] WAIT_DELAY_OS = 6'b100110;  //26

    parameter [5:0] W_ON_O_BRAM = 6'b110000;        //30
    parameter [5:0] SEND_RESULT_TO_BRAM = 6'b110001; //31
    parameter [5:0] SEND_RESULT_TO_BRAM_WS = 6'b110101; //35
    parameter [5:0] DONE = 6'b110010;               //32
    parameter [5:0] DONE_1 = 6'b110011;               //33
    parameter [5:0] DONE_2 = 6'b110100;               //34
    wire [7:0] a_w_en;
    // =========== special purpose bram addr_context ==============
    // 
    // addr 0        = start signal (1: start, 0: do nothing)
    // addr 4  matmul_variable[0] = mode         (1: OS    ,0: WS)
    // addr 8  matmul_variable[1] = M
    // addr 12 matmul_variable[2] = K
    // addr 16 matmul_variable[3] = N
    // ( MxK ) ( KxN ) = (MxN) ;    OS  num_row = M, num_col = N, LENGTH = K
    // ( MxK ) ( MxN ) = (KxN) ;    WS  num_row = M, num_col = N, DEPTH = K(max_8)
    //  =======================
    wire  [5:0]fsm_w_tmp_0;
    wire  [5:0]fsm_w_tmp_1;
    assign fsm_w_tmp_0 = (ARRAY_N==(matmul_variable[1]+1))? STORE_AT_RAM_OS_2:STORE_AT_RAM_OS_1;
    assign fsm_w_tmp_1 = (ARRAY_N==matmul_variable[1])? STORE_AT_RAM_OS_EDGE : fsm_w_tmp_0;

    wire [31:0] contents_num_at_WS;
    assign contents_num_at_WS = (matmul_variable[2] > matmul_variable[3])? matmul_variable[2] : matmul_variable[3];
    wire [31:0] contents_num_at_OS;
    assign contents_num_at_OS = (matmul_variable[1] > matmul_variable[3])? matmul_variable[1] : matmul_variable[3];
    reg [5:0] state; 
    assign DEBUG_state = state;
    // turn on switch
    reg start;
    // ABOUT SP_BRAM
    //=======================
    // always @(posedge clk && start == 0)
    // begin
    //     start <= !reset;//data_out_sp_bram;//data_out_sp_bram;
    // end
    //=======================

    //=======================
    // COUNTER
    reg [31:0] get_var_count; 
    reg [31:0] fill_ram_count; 
    reg [31:0] cycle_count; 
    // INTERNAL REG
    reg [31:0] matmul_variable [NUM_VAR-1:0];
    //DEBUG
    assign DEBUG_matmul_var_1 = matmul_variable[0];
    assign DEBUG_matmul_var_2 = matmul_variable[1];
    assign DEBUG_matmul_var_3 = matmul_variable[2];
    assign DEBUG_matmul_var_4 = matmul_variable[3];


    
    // always @(posedge clk&&!start)
    // begin
    //     start <= data_out_sp_bram;//data_out_sp_bram;
    //     state <= IDLE ;
    // end

    // =========== FSM ==============
    always @(posedge clk)
    begin
        if(start)
        begin
        if(state == IDLE)
        begin

            //tmp 
            // matmul_variable[0] <= 0; //mode OS
            // matmul_variable[1] <= 8; //M
            // matmul_variable[2] <= 8; //K
            // matmul_variable[3] <= 8; //N
            //counter 
            get_var_count <= 0;
            fill_ram_count <= 0;
            cycle_count <= 0;
            //bram
            addr_sp_bram    <= 0;
            
            w_enable_sp_bram <= 'b0;
            data_in_sp_bram <= 0;
            addr_a_bram     <= 0;
            enable_a_bram   <= 1;
            addr_w_bram     <= 0;
            enable_w_bram   <= 1;
            addr_o_bram     <= 0;
            enable_o_bram   <= 1;
            w_enable_o_bram <= 0;
            //system
            system_reset<= 1;
            a_buf_on    <= 0;
            a_base_addr <= 0;
            a_num_rows  <= matmul_variable[1];
            mode        <= matmul_variable[0];
            w_buf_on    <= 0;
            w_base_addr <= 0;
            w_num_cols  <= matmul_variable[3];
            operation_signal_in <= 0;
            o_idx_gen_on<= 0;
            o_ag_o_on   <= 0;
            o_drain     <= 0;
            o_base_addr <= 0;
            o_ram_idx   <= 0;
            o_read_addr <= 0;
            start <= data_out_sp_bram;
            state <= (start)? GET_VAR_R_REQ: IDLE;//W_LOAD: IDLE;//W_LOAD: IDLE;//
         end

          if(state == GET_VAR_R_REQ)
          begin
             system_reset <= 0;
             addr_sp_bram <= get_var_count*4+4;                       //addr 4 8 12 ...
             state <= GET_VAR_W_REG ; 
          end

          if(state == GET_VAR_W_REG)
          begin
            
             state <= UPDATE_COUNT;
          end

          if(state == UPDATE_COUNT)
          begin
            matmul_variable[get_var_count] <= data_out_sp_bram;   //reg[0] reg[1] reg[2]...
            get_var_count <= get_var_count + 1;
            state <= (get_var_count == NUM_VAR-1)? DECIDE_MODE : GET_VAR_R_REQ ; 
          end

          if(state == DECIDE_MODE)
          begin
             state <= (matmul_variable[0])? FILL_RAM_OS : FILL_RAM_WS;
          end

          if(state == FILL_RAM_OS)
          begin
             mode        <= 1; //os
             a_base_addr <= 0; //not yet
             a_num_rows  <= matmul_variable[1];
             w_base_addr <= 0; //not yet
             w_num_cols  <= matmul_variable[3];
             o_base_addr <= 0; //not yet
             //
             addr_a_bram <= fill_ram_count*4;
             addr_w_bram <= fill_ram_count*4;
             case (fill_ram_count%matmul_variable[1])
                0: bram_to_a_ram_w_en <= 8'b00000001;
                1: bram_to_a_ram_w_en <= 8'b00000010;
                2: bram_to_a_ram_w_en <= 8'b00000100;
                3: bram_to_a_ram_w_en <= 8'b00001000;
                4: bram_to_a_ram_w_en <= 8'b00010000;
                5: bram_to_a_ram_w_en <= 8'b00100000;
                6: bram_to_a_ram_w_en <= 8'b01000000;
                7: bram_to_a_ram_w_en <= 8'b10000000;
                default: bram_to_a_ram_w_en <= 8'b00000000; // default value when no match is found
            endcase
            case (fill_ram_count%matmul_variable[3])
                0: bram_to_w_ram_w_en <= 8'b00000001;
                1: bram_to_w_ram_w_en <= 8'b00000010;
                2: bram_to_w_ram_w_en <= 8'b00000100;
                3: bram_to_w_ram_w_en <= 8'b00001000;
                4: bram_to_w_ram_w_en <= 8'b00010000;
                5: bram_to_w_ram_w_en <= 8'b00100000;
                6: bram_to_w_ram_w_en <= 8'b01000000;
                7: bram_to_w_ram_w_en <= 8'b10000000;
                default: bram_to_w_ram_w_en <= 8'b00000000; // default value when no match is found
            endcase
             
             state <= (fill_ram_count == matmul_variable[2]*contents_num_at_OS   -1)? WAIT_DELAY_OS : FILL_RAM_OS;
             fill_ram_count <= (fill_ram_count == matmul_variable[2]*contents_num_at_OS   -1)? 'b0: fill_ram_count + 1;

          end
          if(state == WAIT_DELAY_OS)
          begin
            state <= (fill_ram_count == 5   -1)? OS_FLOW_1 : WAIT_DELAY_OS;
            fill_ram_count <= (fill_ram_count == 5   -1)? 'b0: fill_ram_count + 1;
            bram_to_a_ram_w_en <= 8'b00000000;
            bram_to_w_ram_w_en <= 8'b00000000;
          end
          if(state == FILL_RAM_WS)
          begin
             mode        <= 0; //ws
             a_base_addr <= 0;
             a_num_rows  <= matmul_variable[1]; //=W
             w_base_addr <= 0;
             w_num_cols  <= matmul_variable[3]; // = W
             o_base_addr <= 0;
             //
             addr_a_bram <= fill_ram_count*4;
             addr_w_bram <= fill_ram_count*4;
             case (fill_ram_count%matmul_variable[1])
                    0: bram_to_a_ram_w_en <= 8'b00000001;
                    1: bram_to_a_ram_w_en <= 8'b00000010;
                    2: bram_to_a_ram_w_en <= 8'b00000100;
                    3: bram_to_a_ram_w_en <= 8'b00001000;
                    4: bram_to_a_ram_w_en <= 8'b00010000;
                    5: bram_to_a_ram_w_en <= 8'b00100000;
                    6: bram_to_a_ram_w_en <= 8'b01000000;
                    7: bram_to_a_ram_w_en <= 8'b10000000;
                   default: bram_to_a_ram_w_en <= 8'b00000000; // default value when no match is found
                 endcase
                 case (fill_ram_count%matmul_variable[3])
                    0: bram_to_w_ram_w_en <= 8'b00000001;
                    1: bram_to_w_ram_w_en <= 8'b00000010;
                    2: bram_to_w_ram_w_en <= 8'b00000100;
                    3: bram_to_w_ram_w_en <= 8'b00001000;
                    4: bram_to_w_ram_w_en <= 8'b00010000;
                    5: bram_to_w_ram_w_en <= 8'b00100000;
                    6: bram_to_w_ram_w_en <= 8'b01000000;
                    7: bram_to_w_ram_w_en <= 8'b10000000;
                   default: bram_to_w_ram_w_en <= 8'b00000000; // default value when no match is found
                 endcase
             
             state <= (fill_ram_count == contents_num_at_WS*matmul_variable[1]   -1)? WAIT_DELAY_WS : FILL_RAM_WS;
             fill_ram_count <= (fill_ram_count == contents_num_at_WS*matmul_variable[1]   -1)? 'b0: fill_ram_count + 1;
         end
         if(state == WAIT_DELAY_WS)
          begin
            state <= (fill_ram_count == 5   -1)? W_LOAD : WAIT_DELAY_WS;
            fill_ram_count <= (fill_ram_count == 5   -1)? 'b0: fill_ram_count + 1;
            bram_to_a_ram_w_en <= 8'b00000000;
            bram_to_w_ram_w_en <= 8'b00000000;
          end

        //=========================================
        if(state == W_LOAD)
        begin
            //TMP
            system_reset<= 0;
            //TMP
            a_buf_on    <= 0;
            w_buf_on    <= 1;
            operation_signal_in <= 3'b001;
            state <= (cycle_count == (matmul_variable[1]+1  -1))? A_FLOW_1 : W_LOAD;
            cycle_count <= (cycle_count == (matmul_variable[1]+1   -1)) ? 'b0: cycle_count+1;
            //#(6);                       //TODO  W + 1????????????????? W= M;
        end

        if(state == A_FLOW_1)
        begin
            a_buf_on    <= 1;
            w_buf_on    <= 0;
            operation_signal_in <= 3'b000;
            state <= (cycle_count == (matmul_variable[2]-    1))? ((ARRAY_N == matmul_variable[2])? A_FLOW_3 : A_FLOW_2) : A_FLOW_1;
            cycle_count <= (cycle_count == (matmul_variable[2]   -1)) ? 'b0: cycle_count+1;
            //#(ARRAY_N)
        end
        if(state == A_FLOW_2)
        begin
            a_buf_on    <= 0;
            w_buf_on    <= 0;
            operation_signal_in <= 3'b000;
            state <= (cycle_count == ((ARRAY_N-matmul_variable[2])   -1))? A_FLOW_3 : A_FLOW_2;
            cycle_count <= (cycle_count == ((ARRAY_N-matmul_variable[2])   -1)) ? 'b0: cycle_count+1;
            //#(ARRAY_N)
        end

        if(state == A_FLOW_3)
        begin
            o_idx_gen_on<= 1;
            o_ag_o_on   <= 0;
            o_drain     <= 0;
            a_buf_on    <= 0;
            state <= (cycle_count == (DEPTH+matmul_variable[3]   -1))? STORE_AT_RAM_WS : A_FLOW_3;
            cycle_count <= (cycle_count == (DEPTH+matmul_variable[3]   -1)) ? 'b0: cycle_count+1;
            //#(8+5-1)//DEPTH+num_col-1 ==> DEBUG 09 15 WS result drop last elem ==> add 1 cycle more : "DEPTH+num_col"
        end

        if(state == STORE_AT_RAM_WS)
        begin
            o_idx_gen_on<= 0;
            o_drain     <= 1; 
            o_ag_o_on   <= 1;
            state <= (cycle_count == (DEPTH+1   -1))? W_ON_O_BRAM : STORE_AT_RAM_WS;
            cycle_count <= (cycle_count == (DEPTH+1   -1)) ? 'b0: cycle_count+1;
            //#(DEPTH+1)
        end

        //==========================================
        if(state == OS_FLOW_1)
        begin
            //TMP
            system_reset<= 0;
            //TMP
            a_buf_on    <= 1;
            w_buf_on    <= 1;
            operation_signal_in <= 3'b100;
            state <= (cycle_count == (matmul_variable[2]  -1))? OS_FLOW_2 : OS_FLOW_1;
            cycle_count <= (cycle_count == (matmul_variable[2]  -1)) ? 'b0: cycle_count+1;
            // #( K )
        end

        if(state == OS_FLOW_2)    
        begin
            a_buf_on    <= 0;
            w_buf_on    <= 0;
            operation_signal_in <= 3'b100;
            state <= (cycle_count == (matmul_variable[1]+matmul_variable[3]-1   -1))? fsm_w_tmp_1 : OS_FLOW_2;
            cycle_count <= (cycle_count == (matmul_variable[1]+matmul_variable[3]-1   -1)) ? 'b0: cycle_count+1;
            //#(6+6-1) // num_rows + num_cols -1
        end
        if(state == STORE_AT_RAM_OS_1)
        begin
            a_buf_on    <= 0;
            w_buf_on    <= 0;
            operation_signal_in <= 3'b110;
            state <= (cycle_count == (ARRAY_N-matmul_variable[1]-1   -1))? STORE_AT_RAM_OS_2 : STORE_AT_RAM_OS_1;
            cycle_count <= (cycle_count == (ARRAY_N-matmul_variable[1]-1   -1)) ? 'b0: cycle_count+1;
            //#(ARRAY_N - 6 -1) // ARRAY_N - num_rows -1.
        end
        if(state == STORE_AT_RAM_OS_EDGE)
        begin
            a_buf_on    <= 0;
            w_buf_on    <= 0;
            o_idx_gen_on<= 0;
            o_drain     <= 0;
            o_ag_o_on   <= 1;
            operation_signal_in <= 3'b100;   
            state <= STORE_AT_RAM_OS_2;      
        end
        if(state == STORE_AT_RAM_OS_2)
        begin
            o_idx_gen_on<= 0;
            o_drain     <= 0;
            o_ag_o_on   <= 1;
            operation_signal_in <= 3'b110;
            state <= (cycle_count == (matmul_variable[1]+2   -1))? W_ON_O_BRAM : STORE_AT_RAM_OS_2;
            cycle_count <= (cycle_count == (matmul_variable[1]+2   -1)) ? 'b0: cycle_count+1;
            //#(num_rows + 1)  in systolic_system tb        but in here +1cycle more (num_rows+2)  
        end
        
        //=====================================
        if(state == W_ON_O_BRAM)
        begin
            enable_o_bram   <= 'b1;
            w_enable_o_bram <= 'b1111;
            state <= (matmul_variable[0])? SEND_RESULT_TO_BRAM : SEND_RESULT_TO_BRAM_WS;
        end
        if(state == SEND_RESULT_TO_BRAM)
        begin
            //bram
            // addr_sp_bram    <= 0;
            // //enable_sp_bram  = 0;
            // w_enable_sp_bram<= 0;
            // data_in_sp_bram <= 0;
            // addr_a_bram     <= 0;
            // enable_a_bram   <= 0;
            // addr_w_bram     <= 0;
            // enable_w_bram   <= 0;
            addr_o_bram     <= cycle_count*4;
            enable_o_bram   <= 'b1;
            w_enable_o_bram <= 'b1111;

            //system
            a_buf_on    <= 0;
            a_base_addr <= 0;
            a_num_rows  <= 0;
            mode        <= matmul_variable[0];
            w_buf_on    <= 0;
            w_base_addr <= 0;
            w_num_cols  <= 0;
            operation_signal_in <= 0;
            o_idx_gen_on<= 0;
            o_ag_o_on   <= 0;
            o_drain     <= 0;
            o_base_addr <= 0;

            o_ram_idx   <= cycle_count % matmul_variable[3];// % ARRAY_M;
            o_read_addr <= (cycle_count / matmul_variable[3]);// / ARRAY_M);
            //FOR OS MODE
            state <= (cycle_count == (matmul_variable[3] * matmul_variable[1]   -1))? DONE : SEND_RESULT_TO_BRAM;
            cycle_count <= (cycle_count == (matmul_variable[3] * matmul_variable[1]   -1)) ? 'b0: cycle_count+1;
        end
        if(state == SEND_RESULT_TO_BRAM_WS)
        begin
            addr_o_bram     <= cycle_count*4;
            enable_o_bram   <= 'b1;
            w_enable_o_bram <= 'b1111;

            //system
            a_buf_on    <= 0;
            a_base_addr <= 0;
            a_num_rows  <= 0;
            mode        <= matmul_variable[0];
            w_buf_on    <= 0;
            w_base_addr <= 0;
            w_num_cols  <= 0;
            operation_signal_in <= 0;
            o_idx_gen_on<= 0;
            o_ag_o_on   <= 0;
            o_drain     <= 0;
            o_base_addr <= 0;

            o_ram_idx   <= cycle_count % matmul_variable[3];// % ARRAY_M;
            o_read_addr <= (cycle_count / matmul_variable[3]);// / ARRAY_M);
            //FOR OS MODE
            state <= (cycle_count == (matmul_variable[3] * matmul_variable[2]   -1))? DONE : SEND_RESULT_TO_BRAM_WS;
            cycle_count <= (cycle_count == (matmul_variable[3] * matmul_variable[2]   -1)) ? 'b0: cycle_count+1;
        end

        if(state ==DONE)
        begin
            enable_sp_bram  = 1;
            state <= DONE_1;
            w_enable_sp_bram <= 4'b1111;
            //set end flag
        end
        if(state ==DONE_1)
        begin
            state <= DONE_2; 
            addr_sp_bram    <= 100;
            data_in_sp_bram <= 1;
            //set end flag
        end
        if(state ==DONE_2)
        begin
            state <= IDLE; 
            addr_sp_bram    <= 0;
            data_in_sp_bram <= 0;
            start <= 0;
            state <= (cycle_count == (4   -1))? DONE_2 : DONE_2; //TODO IDLE
            cycle_count <= (cycle_count == (4   -1)) ? 'b0: cycle_count+1;
            //set end flag
        end
                
        end
        else
        begin
            //tmp 
            matmul_variable[0] <= 0; //mode OS
            matmul_variable[1] <= 8; //M
            matmul_variable[2] <= 8; //K
            matmul_variable[3] <= 8; //N
            //counter 
            get_var_count <= 0;
            fill_ram_count <= 0;
            cycle_count <= 0;
            //bram
            addr_sp_bram    <= 0;
            enable_sp_bram  = 1;
            w_enable_sp_bram <= 'b0;
            data_in_sp_bram <= 0;
            addr_a_bram     <= 0;
            enable_a_bram   <= 1;
            addr_w_bram     <= 0;
            enable_w_bram   <= 1;
            addr_o_bram     <= 0;
            enable_o_bram   <= 1;
            w_enable_o_bram <= 0;
            //system
            system_reset<= 1;
            a_buf_on    <= 0;
            a_base_addr <= 0;
            a_num_rows  <= matmul_variable[1];
            mode        <= matmul_variable[0];
            w_buf_on    <= 0;
            w_base_addr <= 0;
            w_num_cols  <= matmul_variable[3];
            operation_signal_in <= 0;
            o_idx_gen_on<= 0;
            o_ag_o_on   <= 0;
            o_drain     <= 0;
            o_base_addr <= 0;
            o_ram_idx   <= 0;
            o_read_addr <= 0;
            start <= data_out_sp_bram;//data_out_sp_bram;
            state <= IDLE ;
        end

    end
    

endmodule