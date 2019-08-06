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
	loff_t offseti = 0;
	loff_t offseto = 0;

	char *token = NULL;
	char *pout = NULL;
	char *pin = NULL;
	char *fout = NULL;
	char *fin = NULL;
	struct stat stat;
	char *endptr;

	if (argc < 3) {
		fprintf(stderr, "Usage: %s <destination[:offset]> <source[:offset]>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	pout = strdup(argv[1]);
	pin = strdup(argv[2]);

	fout = strsep(&pout, ":");
	token = strsep(&pout, ":");
	if (token != NULL)
		offseto = strtoll(token, &endptr, 0);

	fin = strsep(&pin, ":");
	token = strsep(&pin, ":");
	if (token != NULL)
		offseti = strtoll(token, &endptr, 0);

	fd_out = open(fout, O_RDWR, 0666);
	if (fd_out == -1) {
		perror("open fout");
		exit(EXIT_FAILURE);
	}

	if (strcmp("-", fin) == 0) {
		fd_in = fd_out;
	} else {
		fd_in = open(fin, O_RDONLY);
		if (fd_in == -1) {
			perror("open fin)");
			exit(EXIT_FAILURE);
		}
	}

	if (fstat(fd_in, &stat) == -1) {
		perror("fstat");
		exit(EXIT_FAILURE);
	}
	len = stat.st_size;

	if (fd_in == fd_out && offseto == 0)
		offseto=len;

	do {
		ret = copy_file_range(fd_in, &offseti, fd_out, &offseto, len, 0);
		if (ret == -1) {
			perror("copy_file_range");
			exit(EXIT_FAILURE);
		}

	        printf("ret=%d\n",ret);
		len -= ret;
	} while (len > 0);

	close(fd_in);
	if (fd_in != fd_out)
		close(fd_out);
	exit(EXIT_SUCCESS);
}
