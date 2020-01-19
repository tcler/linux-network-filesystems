/*
 * a syscall wrapper in C for copy_file_range(2) test
 * author: Jianhong Yin <yin-jianhong@163.com>
 */

#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <string.h>

ssize_t copy_file_range(int fd_in, loff_t *off_in,
			int fd_out, loff_t *off_out,
			size_t len, unsigned int flags)
{
#ifndef __NR_copy_file_range
#define __NR_copy_file_range 326
#endif

	return syscall(__NR_copy_file_range, fd_in, off_in, fd_out,
		       off_out, len, flags);
}

int main(int argc, char **argv)
{
	unsigned len, ret;
	int fd_in;
	int fd_out;
	loff_t off_in = 0;
	loff_t off_out = 0;

	char *dst = NULL;
	char *src = NULL;
	char *dst_file = NULL;
	char *src_file = NULL;
	char *dst_off = NULL;
	char *src_off = NULL;
	struct stat stat;
	char *endptr;

	if (argc < 3) {
		fprintf(stderr, "Usage: %s <destination[:offset]> <<source|->[:offset]> [len]\n", argv[0]);
		fprintf(stderr, "`note: source is '-' means that 'fd_in' equal 'fd_out' # see copy_file_range(2)\n");
		fprintf(stderr, "  e.g1: %s testfile:256  -  64\n", argv[0]);
		fprintf(stderr, "  e.g2: %s fileout  filein  1024\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	dst = strdup(argv[1]);
	src = strdup(argv[2]);

	dst_file = strsep(&dst, ":");
	dst_off = strsep(&dst, ":");
	if (dst_off != NULL)
		off_out = strtoll(dst_off, &endptr, 0);

	src_file = strsep(&src, ":");
	src_off = strsep(&src, ":");
	if (src_off != NULL)
		off_in = strtoll(src_off, &endptr, 0);

	fd_out = open(dst_file, O_RDWR|O_CREAT, 0666);
	if (fd_out == -1) {
		perror("open dst file");
		exit(EXIT_FAILURE);
	}

	if (strcmp("-", src_file) == 0 || src_file[0] == '\0') {
		fd_in = fd_out;
	} else {
		fd_in = open(src_file, O_RDONLY);
		if (fd_in == -1) {
			perror("open src file)");
			exit(EXIT_FAILURE);
		}
	}

	if (fstat(fd_in, &stat) == -1) {
		perror("fstat");
		exit(EXIT_FAILURE);
	}
	len = stat.st_size;

	if (fd_in == fd_out && dst_off == NULL)
		off_out=len;

	if (argv[3] != NULL) {
		len = strtoll(argv[3], &endptr, 0);
	}

	do {
		ret = copy_file_range(fd_in, &off_in, fd_out, &off_out, len, 0);
		if (ret == -1) {
			perror("copy_file_range");
			exit(EXIT_FAILURE);
		}
	        printf("ret=%d, len=%zu\n", ret, len);
		if (ret == 0)
			break;
		len -= ret;
	} while (len > 0);

	close(fd_in);
	if (fd_in != fd_out)
		close(fd_out);
	exit(EXIT_SUCCESS);
}
