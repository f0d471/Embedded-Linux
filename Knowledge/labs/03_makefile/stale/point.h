/* 两个 .c 共用的结构体。实验时在 x 前面加一个字段,看只重编一半会怎样 */
struct point {
    int x, y;
};

void fill(struct point *p);
