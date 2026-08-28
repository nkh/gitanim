/* pp_reorder.c — standalone layer: 4-sweep reorder + position adjust */
#include "pp_common.h"

int main(void) {
    char line[PP_MAX_LINE];
    Op *ops = NULL;
    int n_ops = 0, ops_cap = 0, in_hunk = 0;
    Hunk hunk = {0};
    int line_offset = 0;

    ops_cap = 4096;
    ops = (Op *)malloc(ops_cap * sizeof(Op));

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n\r")] = 0;
        if (line[0] == 0) continue;
        if (line[0] == '#') {
            if (strstr(line,"raw diff")||strstr(line,"post-processed"))
                printf("# diffvim post-processed v2\n");
            else printf("%s\n", line);
            continue;
        }
        if (strncmp(line,"HUNK\t",5)==0) {
            if (in_hunk && n_ops > 0) {
                for (int j=0;j<n_ops;j++) ops[j].line += line_offset;
                Op *out = (Op *)malloc((n_ops+1024)*sizeof(Op));
                int n_out = 0, buf_start = 0;
                /* 4-sweep reorder */
                for (int i=0;i<=n_ops;i++) {
                    int is_flush = (i==n_ops);
                    if (i<n_ops && !pp_is_debug_op(&ops[i]))
                        if (strcmp(ops[i].type,"keep")==0||ops[i].code==10) is_flush=1;
                    if (is_flush) {
                        for (int j=buf_start;j<i;j++) if(strcmp(ops[j].type,"delete")==0&&ops[j].code!=10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if((strcmp(ops[j].type,"insert")==0||strcmp(ops[j].type,"overwrite_insert")==0)&&ops[j].code!=10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if(strcmp(ops[j].type,"delete")==0&&ops[j].code==10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if((strcmp(ops[j].type,"insert")==0||strcmp(ops[j].type,"overwrite_insert")==0)&&ops[j].code==10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if(pp_is_debug_op(&ops[j])&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        if (i<n_ops&&n_out<n_ops+1024) out[n_out++]=ops[i];
                        buf_start=i+1;
                    }
                }
                /* Set positions */
                { int cl=n_out>0?out[0].line:1, cc=1;
                  for (int i=0;i<n_out;i++) {
                      if (pp_is_debug_op(&out[i])) continue;
                      out[i].line=cl; out[i].col=cc;
                      if (strcmp(out[i].type,"keep")==0) { if(out[i].code==10){cl++;cc=1;}else cc++; }
                      else if (strcmp(out[i].type,"insert")==0||strcmp(out[i].type,"overwrite_insert")==0) { if(out[i].code==10){cl++;cc=1;}else cc++; }
                  }
                }
                /* Update line_offset */
                { int ni=0,nd=0; for(int j=0;j<n_out;j++){if(strcmp(out[j].type,"insert")==0&&out[j].code==10)ni++;if(strcmp(out[j].type,"delete")==0&&out[j].code==10)nd++;} line_offset+=ni-nd; }
                pp_write_hunk(&hunk);
                for (int i=0;i<n_out;i++) pp_write_op(&out[i]);
                pp_write_hunk_end();
                free(out);
            }
            sscanf(line,"HUNK\t%d\t%d\t%d\t%d\t%d",&hunk.target,&hunk.del,&hunk.ins,&hunk.end_ins,&hunk.end_del);
            in_hunk=1; n_ops=0; continue;
        }
        if (strncmp(line,"HUNK_END",8)==0) {
            if (in_hunk && n_ops > 0) {
                for (int j=0;j<n_ops;j++) ops[j].line += line_offset;
                Op *out = (Op *)malloc((n_ops+1024)*sizeof(Op));
                int n_out = 0, buf_start = 0;
                for (int i=0;i<=n_ops;i++) {
                    int is_flush = (i==n_ops);
                    if (i<n_ops && !pp_is_debug_op(&ops[i]))
                        if (strcmp(ops[i].type,"keep")==0||ops[i].code==10) is_flush=1;
                    if (is_flush) {
                        for (int j=buf_start;j<i;j++) if(strcmp(ops[j].type,"delete")==0&&ops[j].code!=10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if((strcmp(ops[j].type,"insert")==0||strcmp(ops[j].type,"overwrite_insert")==0)&&ops[j].code!=10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if(strcmp(ops[j].type,"delete")==0&&ops[j].code==10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if((strcmp(ops[j].type,"insert")==0||strcmp(ops[j].type,"overwrite_insert")==0)&&ops[j].code==10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        for (int j=buf_start;j<i;j++) if(pp_is_debug_op(&ops[j])&&n_out<n_ops+1024) out[n_out++]=ops[j];
                        if (i<n_ops&&n_out<n_ops+1024) out[n_out++]=ops[i];
                        buf_start=i+1;
                    }
                }
                { int cl=n_out>0?out[0].line:1, cc=1;
                  for (int i=0;i<n_out;i++) {
                      if (pp_is_debug_op(&out[i])) continue;
                      out[i].line=cl; out[i].col=cc;
                      if (strcmp(out[i].type,"keep")==0) { if(out[i].code==10){cl++;cc=1;}else cc++; }
                      else if (strcmp(out[i].type,"insert")==0||strcmp(out[i].type,"overwrite_insert")==0) { if(out[i].code==10){cl++;cc=1;}else cc++; }
                  }
                }
                { int ni=0,nd=0; for(int j=0;j<n_out;j++){if(strcmp(out[j].type,"insert")==0&&out[j].code==10)ni++;if(strcmp(out[j].type,"delete")==0&&out[j].code==10)nd++;} line_offset+=ni-nd; }
                pp_write_hunk(&hunk);
                for (int i=0;i<n_out;i++) pp_write_op(&out[i]);
                pp_write_hunk_end();
                free(out);
            }
            in_hunk=0; n_ops=0; continue;
        }
        if (in_hunk) {
            if (n_ops>=ops_cap) { ops_cap*=2; ops=(Op *)realloc(ops,ops_cap*sizeof(Op)); }
            pp_parse_op(line, &ops[n_ops]); n_ops++;
        }
    }
    if (in_hunk && n_ops > 0) {
        for (int j=0;j<n_ops;j++) ops[j].line += line_offset;
        Op *out = (Op *)malloc((n_ops+1024)*sizeof(Op));
        int n_out = 0, buf_start = 0;
        for (int i=0;i<=n_ops;i++) {
            int is_flush = (i==n_ops);
            if (i<n_ops && !pp_is_debug_op(&ops[i]))
                if (strcmp(ops[i].type,"keep")==0||ops[i].code==10) is_flush=1;
            if (is_flush) {
                for (int j=buf_start;j<i;j++) if(strcmp(ops[j].type,"delete")==0&&ops[j].code!=10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                for (int j=buf_start;j<i;j++) if((strcmp(ops[j].type,"insert")==0||strcmp(ops[j].type,"overwrite_insert")==0)&&ops[j].code!=10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                for (int j=buf_start;j<i;j++) if(strcmp(ops[j].type,"delete")==0&&ops[j].code==10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                for (int j=buf_start;j<i;j++) if((strcmp(ops[j].type,"insert")==0||strcmp(ops[j].type,"overwrite_insert")==0)&&ops[j].code==10&&n_out<n_ops+1024) out[n_out++]=ops[j];
                for (int j=buf_start;j<i;j++) if(pp_is_debug_op(&ops[j])&&n_out<n_ops+1024) out[n_out++]=ops[j];
                if (i<n_ops&&n_out<n_ops+1024) out[n_out++]=ops[i];
                buf_start=i+1;
            }
        }
        { int cl=n_out>0?out[0].line:1, cc=1;
          for (int i=0;i<n_out;i++) {
              if (pp_is_debug_op(&out[i])) continue;
              out[i].line=cl; out[i].col=cc;
              if (strcmp(out[i].type,"keep")==0) { if(out[i].code==10){cl++;cc=1;}else cc++; }
              else if (strcmp(out[i].type,"insert")==0||strcmp(out[i].type,"overwrite_insert")==0) { if(out[i].code==10){cl++;cc=1;}else cc++; }
          }
        }
        pp_write_hunk(&hunk);
        for (int i=0;i<n_out;i++) pp_write_op(&out[i]);
        pp_write_hunk_end();
        free(out);
    }
    printf("\n"); free(ops); return 0;
}
