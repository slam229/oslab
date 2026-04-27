#include "asm_utils.h"
#include "interrupt.h"
#include "stdio.h"
#include "program.h"
#include "thread.h"
#include "sync.h"

// 屏幕IO处理器
STDIO stdio;
// 中断管理器
InterruptManager interruptManager;
// 程序管理器
ProgramManager programManager;

// ==================== 芝士汉堡问题（信号量互斥） ====================

Semaphore semaphore;
int cheese_burger;

void a_mother(void *arg)
{
    semaphore.P();
    int delay = 0;

    printf("mother: start to make cheese burger, there are %d cheese burger now\n", cheese_burger);
    // make 10 cheese_burger
    cheese_burger += 10;

    printf("mother: oh, I have to hang clothes out.\n");
    // hanging clothes out
    delay = 0xfffffff;
    while (delay)
        --delay;
    // done

    printf("mother: Oh, Jesus! There are %d cheese burgers\n", cheese_burger);
    semaphore.V();
}

void a_naughty_boy(void *arg)
{
    semaphore.P();
    printf("boy   : Look what I found!\n");
    // eat all cheese_burgers out secretly
    cheese_burger -= 10;
    // run away as fast as possible
    semaphore.V();
}

// ==================== 生产者-消费者问题（有界缓冲区） ====================

const int MAX_PHILOSOPHER = 5;         // 哲学家的数量

Semaphore tablewares[MAX_PHILOSOPHER]; // 餐具

int eatingCount = 0;
Semaphore eatingCountMutex;


// 简单延时函数
void delay(int count)
{
    volatile int d = count;
    while (d) --d;
}

void philosopher(void * arg){
    int id = (int)arg;
    int left = id; // 左手餐具编号
    int right = (id + 1) % MAX_PHILOSOPHER; // 右手餐具编号

    while (true) {
        printf("Philosopher %d is thinking.\n", id);
        delay(0xfffffff); // 思考一段时间

        // 尝试拿起餐具
        while(true){
            eatingCountMutex.P();
            if(eatingCount < MAX_PHILOSOPHER - 1){ // 最多允许4个哲学家同时吃饭
                eatingCount++;
                eatingCountMutex.V();
                break;
            }
            eatingCountMutex.V();
            printf("Already %d philosophers are eating, philosopher %d waiting...\n", eatingCount, id);
            delay(0xeffffff); // 等待一段时间后重试
        }
        printf("Philosopher %d try to take left tableware.\n", id);
        tablewares[left].P();
        delay(0xfffffff); // 思考一段时间
        printf("Philosopher %d try to take right tableware.\n", id);
        tablewares[right].P();

        // 吃饭
        printf("Philosopher %d is eating.\n", id);
        delay(0xfffffff); // 吃饭一段时间

        // 放下餐具
        tablewares[right].V();
        tablewares[left].V();

        eatingCountMutex.P();
        eatingCount--;
        eatingCountMutex.V();
    }
}

// ==================== 主线程 ====================

void first_thread(void *arg)
{
    // 清屏
    stdio.moveCursor(0);
    for (int i = 0; i < 25 * 80; ++i)
    {
        stdio.print(' ');
    }
    stdio.moveCursor(0);

    // ---- Part 1: 芝士汉堡问题 ----
    printf("===== Part 1: Cheese Burger (Semaphore Mutex) =====\n");
    cheese_burger = 0;
    semaphore.initialize(1);

    programManager.executeThread(a_mother, nullptr, "mother", 1);
    programManager.executeThread(a_naughty_boy, nullptr, "boy", 1);

    // 等待芝士汉堡问题的两个线程执行完毕
    delay(0x3fffffff);

    printf("==== Part 2: Dining Philosophers =====\n");
    
    for(int i=0; i < MAX_PHILOSOPHER; ++i){
        tablewares[i].initialize(1); // 初始化餐具信号量
    }
    eatingCount = 0;
    eatingCountMutex.initialize(1);

    for(int i=0; i < MAX_PHILOSOPHER; ++i){
        programManager.executeThread(philosopher, (void*)i, "philosopher", 1);
    }

    asm_halt();
}

// ==================== 内核入口 ====================

extern "C" void setup_kernel()
{
    // 中断管理器
    interruptManager.initialize();
    interruptManager.enableTimeInterrupt();
    interruptManager.setTimeInterrupt((void *)asm_time_interrupt_handler);

    // 输出管理器
    stdio.initialize();

    // 进程/线程管理器
    programManager.initialize();

    // 创建第一个线程
    int pid = programManager.executeThread(first_thread, nullptr, "first thread", 1);
    if (pid == -1)
    {
        printf("can not execute thread\n");
        asm_halt();
    }

    ListItem *item = programManager.readyPrograms.front();
    PCB *firstThread = ListItem2PCB(item, tagInGeneralList);
    firstThread->status = RUNNING;
    programManager.readyPrograms.pop_front();
    programManager.running = firstThread;
    asm_switch_thread(0, firstThread);

    asm_halt();
}
