#include "sync.h"
#include "asm_utils.h"
#include "stdio.h"
#include "os_modules.h"
#include "program.h"

SpinLock::SpinLock()
{
    initialize();
}

void SpinLock::initialize()
{
    bolt = 0;
}

// void SpinLock::lock()
// {
//     uint32 key = 1;

//     do
//     {
//         asm_atomic_exchange(&key, &bolt);
//         //printf("pid: %d\n", programManager.running->pid);
//     } while (key);
// }

/**
    作业 1.2
    * Compare and Swap实现自旋锁
    * 通过CAS原子操作来实现自旋锁的获取和释放，避免了传统测试并设置方法中的竞态条件。
    * 在lock函数中，线程尝试将bolt从0修改为1，如果成功则获得锁；如果失败则继续尝试，直到获得锁。
    * 在unlock函数中，直接将bolt设置为0，释放锁。
*/
void SpinLock::lock()
{
    while (asm_cas(&bolt, 0, 1) != 0)
        ;
}

void SpinLock::unlock()
{
    bolt = 0;
}

Semaphore::Semaphore()
{
    initialize(0);
}

void Semaphore::initialize(uint32 counter)
{
    this->counter = counter;
    semLock.initialize();
    waiting.initialize();
}

void Semaphore::P()
{
    PCB *cur = nullptr;

    while (true)
    {
        semLock.lock();
        if (counter > 0)
        {
            --counter;
            semLock.unlock();
            return;
        }

        cur = programManager.running;
        waiting.push_back(&(cur->tagInGeneralList));
        cur->status = ProgramStatus::BLOCKED;

        semLock.unlock();
        programManager.schedule();
    }
}

void Semaphore::V()
{
    semLock.lock();
    ++counter;
    if (waiting.size())
    {
        PCB *program = ListItem2PCB(waiting.front(), tagInGeneralList);
        waiting.pop_front();
        semLock.unlock();
        programManager.MESA_WakeUp(program);
    }
    else
    {
        semLock.unlock();
    }
}