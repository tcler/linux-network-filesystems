#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/delay.h>

#include "offset.h"

static int delay = 1000;
module_param(delay, int, 0644);

static struct kprobe kp = {
/*
 * 0xffffffffc04e1761 <nfs4_get_open_state+305>:   mov    %rcx,0x8(%r13)
 * 0xffffffffc04e1765 <nfs4_get_open_state+309>:   mov    %r14,%rdi
 * 0xffffffffc04e1768 <nfs4_get_open_state+312>:   callq  0xffffffff8132b250 <ihold>
 * 0xffffffffc04e176d <nfs4_get_open_state+317>:   mov    %r14,0x38(%r12)
 */
	.symbol_name	= "nfs4_get_open_state",
	.offset = OFFSET,
};

static int handler_pre(struct kprobe *p, struct pt_regs *regs)
{
#ifdef CONFIG_X86
	pr_info("<%s> pre_handler: p->addr = 0x%p, ip = %lx, flags = 0x%lx delay = %d\n",
		p->symbol_name, p->addr, regs->ip, regs->flags, delay);
#endif
#ifdef CONFIG_ARM64
	pr_info("<%s> pre_handler: p->addr = 0x%p, pc = 0x%lx delay = %d,"
			" pstate = 0x%lx\n",
		p->symbol_name, p->addr, (long)regs->pc, (long)regs->pstate, delay);
#endif
	mdelay(delay);

	return 0;
}

static int handler_fault(struct kprobe *p, struct pt_regs *regs, int trapnr)
{
	pr_info("fault_handler: p->addr = 0x%p, trap #%dn", p->addr, trapnr);
	return 0;
}

static int __init kprobe_init(void)
{
	int ret;
	kp.pre_handler = handler_pre;
	kp.fault_handler = handler_fault;

	ret = register_kprobe(&kp);
	if (ret < 0) {
		pr_err("register_kprobe failed, returned %d\n", ret);
		return ret;
	}
	pr_info("Planted kprobe at %p\n", kp.addr);
	return 0;
}

static void __exit kprobe_exit(void)
{
	unregister_kprobe(&kp);
	pr_info("kprobe at %p unregistered\n", kp.addr);
}

module_init(kprobe_init)
module_exit(kprobe_exit)
MODULE_LICENSE("GPL");
