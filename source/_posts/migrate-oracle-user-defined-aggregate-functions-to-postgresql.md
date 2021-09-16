---
title: "Oracle 迁移 PostgreSQL - 自定义聚合函数"
date: 2021-09-22 22:05:49 +0800
categories: 数据库
tags:
  - Oracle
  - PostgreSQL
  - 迁移
---

数据库通常都提供了一系列预定义的聚合函数（Aggregate Functions），例如 MAX，MIN，SUM 等，它们对一组数据进行操作。这些预定义的聚合函数通常只能处理标量类型，不能处理诸如对象类型等复杂的数据类型，当前大部分数据库都提供了为复杂数据类型自定义聚合函数（User-Defined Aggregate Functions）的功能。本文简要介绍 Oracle 中的自定义聚合函数以及如何迁移到 PostgreSQL 数据库中。

<!--more-->

## Oracle 自定义聚合函数

在 Oracle 数据库中要实现自定义聚合函数，我们需要实现下面的 `ODCIAggregate` 接口。

* `ODCIAggregateInitialize` - 初始化用户自定义聚合函数的状态，并返回该状态。
* `ODCIAggregateIterate` - 反复调用该函数来更新聚合函数状态。在每次调用时，一个新的值和聚合状态被传递进来。该函数处理新值并返回更新后的聚合状态。该函数对于数据库组中的每一个非 NULL 值都会被调用。NULL 值在聚合过程中被忽略，并且不被传递给该函数。
* `ODCIAggregateMerge` - 这是一个可选的函数，它用于并行执行聚合函数，当并行执行的聚合函数完成之后，我们需要通过该函数将两个聚合状态进行合并，并返回一个新的聚合状态。
* `ODCIAggregateTerminate` - 聚合函数的最后一步，该例函数将聚合状态作为输入，并返回聚合值。

例如，我们要执行下面的查询：

```sql
SELECT AVG(t.sales) FROM AnnualSales t GROUP BY t.state;
```

聚合函数 `AVG()` 的执行过程如下所示：

1. **初始化**。该聚合函数可能包含两个状态：`runningSum` 和 `runningCount`
   ```
   runningSum = 0;
   runningCount = 0;
   ```
2. **循环迭代**。对每个连续的输入值进行处理，并更新状态：
   ```
   runningSum += val;
   runningCount++;
   ```
3. **终止**。计算结果。更加聚合状态返回聚合值：
    ```
	if (runningCount > 0) {
	    return runningSum / runningCount;
	}
	return NULL;
	```

在上面的情况我们并有**合并**的过程。如果有合并的需求，其形式如下：

* **合并**。合并两个聚合状态并返回新的聚合状态。
  ```
  runningSum = runningSum1 + runningSum2;
  runningCount = runningCount1 + runningCount2;
  ```

### 创建聚合函数

Oracle 中的聚合函数创建分为两步：实现聚合函数接口和创建用户自定义聚合函数。

#### 实现聚合函数接口

正如上面所说，我们需要实现上述 4 个接口。Oracle 将其分为两部分 `TYPE` 和 `TYPE BODY`。

```
CREATE TYPE SpatialUnionRoutines(
    STATIC FUNCTION ODCIAggregateInitialize( ... ) ...,
    MEMBER FUNCTION ODCIAggregateIterate(...) ... ,
    MEMBER FUNCTION ODCIAggregateMerge(...) ...,
    MEMBER FUNCTION ODCIAggregateTerminate(...)
);

CREATE TYPE BODY SpatialUnionRoutines IS
    ...
END;
```

#### 创建聚合函数


此步骤通过指定其签名和实现 `ODCIAggregate` 接口的对象类型来创建 `SpatialUnion()` 聚合函数。

```
CREATE FUNCTION SpatialUnion(x Geometry) RETURN Geometry
AGGREGATE USING SpatialUnionRoutines;
```

如果我们想要聚合函数执行并行，那么我们需要加上 `PARALLEL_ENABLE` 选项。

```
CREATE FUNCTION SpatialUnion(x Geometry) RETURN Geometry
PARALLEL_ENABLE AGGREGATE USING SpatialUnionRoutines;
```

### 示例

这个例子说明了如何创建一个简单的用户定义的聚合函数 `SecondMax()`，以返回一组数字中的第二大值。

首先，我们需要给出 `SecondMaxImpl` 类型的声明，它包含 `ODCIAggregate` 接口声明以及可能会用到的状态信息。

```sql
CREATE TYPE SecondMaxImpl AS OBJECT
(
    max    number, -- highest value seen so far
    secmax number, -- second highest value seen so far

    STATIC FUNCTION ODCIAggregateInitialize(sctx IN OUT SecondMaxImpl)
        RETURN number,
    MEMBER FUNCTION ODCIAggregateIterate(self IN OUT SecondMaxImpl, value IN number)
	    RETURN number,
    MEMBER FUNCTION ODCIAggregateMerge(self IN OUT SecondMaxImpl, ctx2 IN SecondMaxImpl)
	    RETURN number,
    MEMBER FUNCTION ODCIAggregateTerminate(self IN SecondMaxImpl, returnValue OUT number, flags IN number)
	    RETURN number
);
```

接着，我们需要给出 `SecondMaxImpl` 类型的实现。

```sql
CREATE OR REPLACE TYPE BODY SecondMaxImpl IS
    STATIC FUNCTION ODCIAggregateInitialize(sctx IN OUT SecondMaxImpl)
    RETURN number IS
    BEGIN
      sctx := SecondMaxImpl(0, 0);
      return ODCIConst.Success;
    END;

    MEMBER FUNCTION ODCIAggregateIterate(self IN OUT SecondMaxImpl, value IN number)
    RETURN number IS
    BEGIN
        IF value > self.max THEN
            self.secmax := self.max;
            self.max := value;
        ELSIF value > self.secmax THEN
            self.secmax := value;
        END IF;
        return ODCIConst.Success;
    END;

    MEMBER FUNCTION ODCIAggregateMerge(self IN OUT SecondMaxImpl, ctx2 IN SecondMaxImpl)
	RETURN number IS
    BEGIN
        IF ctx2.max > self.max THEN
            IF ctx2.secmax > self.secmax THEN
                self.secmax := ctx2.secmax;
            ELSE
			    self.secmax := self.max;
            END IF;
            self.max := ctx2.max;
        ELSIF ctx2.max > self.secmax THEN
            self.secmax := ctx2.max;
      END IF;
      return ODCIConst.Success;
    END;

    member function ODCIAggregateTerminate(self IN SecondMaxImpl, returnValue OUT number, flags IN number)
	RETURN number IS
    BEGIN
        returnValue := self.secmax;
        return ODCIConst.Success;
    END;
END;
```

最后，创建用户自定义聚合函数。

```sql
CREATE FUNCTION SecondMax(input number) RETURN number
PARALLEL_ENABLE AGGREGATE USING SecondMaxImpl;
```
接着我们就可以使用 `SecondMax()` 聚合函数了。

```sql
SELECT SecondMax(salary), department_id
FROM employees
GROUP BY department_id
HAVING SecondMax(salary) > 9000;

SECONDMAX(SALARY) DEPARTMENT_ID
----------------- -------------
            13500            80
            17000            90
```

## PostgreSQL 自定义聚合函数

在 PostgreSQL 中，我们可以通过 [`CREATE AGGREGATE`](https://www.postgresql.org/docs/13/sql-createaggregate.html) 命令来创建自定义聚合函数，PostgreSQL 中对于聚合函数的自定义提供了多个接口，例如 `sfunc`，`finalfunc`, `combinefunc` 等。PostgreSQL 中的聚合函数必须要提供两个值：`sfunc` 和 `stype`。

* **`sfunc`** - 这是一个函数接口，它将根据当前的状态值以及新到来的数据得到下一步的装置，类似与 Oracle 中的 `ODCIAggregateIterate()` 函数。
* **`stype`** - 聚合函数状态值的类型，类似于与 Oracle 中 `type` 的非函数部分。

此外，我们还可能会用到以下参数：

* **`initcond`** - 用于给出聚合函数状态的初始值，作用相当于 Oracle 中的 `ODCIAggregateInitialize()` 函数。
* **`combinefunc`** - 合并两个聚合状态，相当于 Oracle 中的 `ODCIAggregateMerge()` 函数。
* **`finalfunc`** - 根据聚合状态计算聚合值，相当于 Oracle 中的 `ODCIAggregateTerminate()` 函数。

### 迁移 SecondMax

对 PostgreSQL 的自定义聚合函数有了基本的了解，我们来看看如何将上面的 Oracle `SecondMax` 迁移到 PostgreSQL 中。

首先，我们需要两个状态值，`max` 和 `secmax`。我可以通过新建一个类型来实现这个目的。

```sql
CREATE TYPE second_max_state AS (max numeric, secmax numeric);
```

理论上，这里我们可以不必新建一个类型，而是直接使用 `numeric` 的数组也是可以的。为了使其更具一般性，这里采用了新类型的方式。

接着我们需要创建 3 个函数，`sfunc`，`combinefunc` 和 `finalfunc`。我们先看 `sfunc` 函数。

`sfunc` 接收当前状态和当前数据值作为参数，并计算新的状态值。其实现如下所示：

```sql
CREATE OR REPLACE FUNCTION second_max_transition(state second_max_state, value numeric)
RETURNS second_max_state
AS $$
BEGIN
    IF value > state.max THEN
	    state.secmax := state.max;
		state.max := value;
	ELSIF value > state.secmax THEN
	    state.secmax := value;
	END IF;
	RETURN state;
END;
$$ LANGUAGE plpgsql;
```

接着是 `combinefunc` 函数，它合并两个状态并产生新的状态。

```sql
CREATE OR REPLACE FUNCTION second_max_combine(state1 second_max_state, state2 second_max_state)
RETURNS second_max_state
AS $$
BEGIN
    IF state2.max > state1.max THEN
	    IF state2.secmax > state1.secmax THEN
		    state1.secmax := state2.secmax;
		ELSE
		    state1.secmax := state1.max;
		END IF;
		state1.max := state2.max;
	ELSIF state2.max > state1.secmax THEN
	    state1.secmax := state2.max;
	END IF;
	RETURN state1;
END;
$$ LANGUAGE plpgsql;
```

接下来是 `finalfunc` 函数，它接收一个状态作为参数并返回最后的聚合值。

```sql
CREATE OR REPLACE FUNCTION second_max_final(state second_max_state)
RETURNS numeric
AS $$
BEGIN
    RETURN state.secmax;
END;
$$ LANGUAGE plpgsql;
```

最后，我们通过 `CREATE AGGREGATE` 命令创建自定义聚合函数。

```sql
CREATE AGGREGATE second_max(value numeric) (
    stype = second_max_state,
    sfunc = second_max_transition,
    combinefunc = second_max_combine,
    finalfunc = second_max_final,
    initcond = '(0, 0)'
);
```

### 测试

完成上面的步骤之后，执行下面的查询，可以得到和 Oracle 相同的结果。

```sql
SELECT second_max(salary), department_id
FROM employees
ROUP BY department_id
AVING second_max(salary) > 9000;
 second_max | department_id
------------+---------------
   13500.00 |            80
   17000.00 |            90
(2 rows)
```

## 测试数据

该测试数据来自 Oracle 数据库中的 `HR.EMPLOYEES` 表。

PostgreSQL 数据库中表结构如下所示：

```sql
CREATE TABLE employees (
    employee_id numeric(6,0) NOT NULL,
    first_name varchar(20),
    last_name varchar(25) NOT NULL,
    email varchar(25) NOT NULL,
    phone_number varchar(20),
    hire_date date NOT NULL,
    job_id varchar(10) NOT NULL,
    salary numeric(8,2),
    commission_pct numeric(2,2),
    manager_id numeric(6,0),
    department_id numeric(4,0)
);
```

Oracle 数据库中表结构如下所示：

```sql
CREATE TABLE employees (
    employee_id number(6,0) NOT NULL,
    first_name varchar2(20 byte),
    last_name varchar2(25 byte) NOT NULL,
    email varchar2(25 byte) NOT NULL,
    phone_number varchar2(20 byte),
    hire_date date NOT NULL,
    job_id varchar2(10 byte) NOT NULL,
    salary number(8,2),
    commission_pct number(2,2),
    manager_id number(6,0),
    department_id number(4,0)
);
```

数据如下所示：

```sql
INSERT INTO employees VALUES ('100', 'Steven', 'King', 'SKING', '515.123.4567', TO_DATE('1987-06-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'AD_PRES', '24000', NULL, NULL, '90');
INSERT INTO employees VALUES ('101', 'Neena', 'Kochhar', 'NKOCHHAR', '515.123.4568', TO_DATE('1989-09-21 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'AD_VP', '17000', NULL, '100', '90');
INSERT INTO employees VALUES ('102', 'Lex', 'De Haan', 'LDEHAAN', '515.123.4569', TO_DATE('1993-01-13 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'AD_VP', '17000', NULL, '100', '90');
INSERT INTO employees VALUES ('103', 'Alexander', 'Hunold', 'AHUNOLD', '590.423.4567', TO_DATE('1990-01-03 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'IT_PROG', '9000', NULL, '102', '60');
INSERT INTO employees VALUES ('104', 'Bruce', 'Ernst', 'BERNST', '590.423.4568', TO_DATE('1991-05-21 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'IT_PROG', '6000', NULL, '103', '60');
INSERT INTO employees VALUES ('105', 'David', 'Austin', 'DAUSTIN', '590.423.4569', TO_DATE('1997-06-25 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'IT_PROG', '4800', NULL, '103', '60');
INSERT INTO employees VALUES ('106', 'Valli', 'Pataballa', 'VPATABAL', '590.423.4560', TO_DATE('1998-02-05 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'IT_PROG', '4800', NULL, '103', '60');
INSERT INTO employees VALUES ('107', 'Diana', 'Lorentz', 'DLORENTZ', '590.423.5567', TO_DATE('1999-02-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'IT_PROG', '4200', NULL, '103', '60');
INSERT INTO employees VALUES ('108', 'Nancy', 'Greenberg', 'NGREENBE', '515.124.4569', TO_DATE('1994-08-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'FI_MGR', '12000', NULL, '101', '100');
INSERT INTO employees VALUES ('109', 'Daniel', 'Faviet', 'DFAVIET', '515.124.4169', TO_DATE('1994-08-16 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'FI_ACCOUNT', '9000', NULL, '108', '100');
INSERT INTO employees VALUES ('110', 'John', 'Chen', 'JCHEN', '515.124.4269', TO_DATE('1997-09-28 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'FI_ACCOUNT', '8200', NULL, '108', '100');
INSERT INTO employees VALUES ('111', 'Ismael', 'Sciarra', 'ISCIARRA', '515.124.4369', TO_DATE('1997-09-30 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'FI_ACCOUNT', '7700', NULL, '108', '100');
INSERT INTO employees VALUES ('112', 'Jose Manuel', 'Urman', 'JMURMAN', '515.124.4469', TO_DATE('1998-03-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'FI_ACCOUNT', '7800', NULL, '108', '100');
INSERT INTO employees VALUES ('113', 'Luis', 'Popp', 'LPOPP', '515.124.4567', TO_DATE('1999-12-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'FI_ACCOUNT', '6900', NULL, '108', '100');
INSERT INTO employees VALUES ('114', 'Den', 'Raphaely', 'DRAPHEAL', '515.127.4561', TO_DATE('1994-12-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PU_MAN', '11000', NULL, '100', '30');
INSERT INTO employees VALUES ('115', 'Alexander', 'Khoo', 'AKHOO', '515.127.4562', TO_DATE('1995-05-18 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PU_CLERK', '3100', NULL, '114', '30');
INSERT INTO employees VALUES ('116', 'Shelli', 'Baida', 'SBAIDA', '515.127.4563', TO_DATE('1997-12-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PU_CLERK', '2900', NULL, '114', '30');
INSERT INTO employees VALUES ('117', 'Sigal', 'Tobias', 'STOBIAS', '515.127.4564', TO_DATE('1997-07-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PU_CLERK', '2800', NULL, '114', '30');
INSERT INTO employees VALUES ('118', 'Guy', 'Himuro', 'GHIMURO', '515.127.4565', TO_DATE('1998-11-15 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PU_CLERK', '2600', NULL, '114', '30');
INSERT INTO employees VALUES ('119', 'Karen', 'Colmenares', 'KCOLMENA', '515.127.4566', TO_DATE('1999-08-10 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PU_CLERK', '2500', NULL, '114', '30');
INSERT INTO employees VALUES ('120', 'Matthew', 'Weiss', 'MWEISS', '650.123.1234', TO_DATE('1996-07-18 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_MAN', '8000', NULL, '100', '50');
INSERT INTO employees VALUES ('121', 'Adam', 'Fripp', 'AFRIPP', '650.123.2234', TO_DATE('1997-04-10 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_MAN', '8200', NULL, '100', '50');
INSERT INTO employees VALUES ('122', 'Payam', 'Kaufling', 'PKAUFLIN', '650.123.3234', TO_DATE('1995-05-01 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_MAN', '7900', NULL, '100', '50');
INSERT INTO employees VALUES ('123', 'Shanta', 'Vollman', 'SVOLLMAN', '650.123.4234', TO_DATE('1997-10-10 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_MAN', '6500', NULL, '100', '50');
INSERT INTO employees VALUES ('124', 'Kevin', 'Mourgos', 'KMOURGOS', '650.123.5234', TO_DATE('1999-11-16 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_MAN', '5800', NULL, '100', '50');
INSERT INTO employees VALUES ('125', 'Julia', 'Nayer', 'JNAYER', '650.124.1214', TO_DATE('1997-07-16 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3200', NULL, '120', '50');
INSERT INTO employees VALUES ('126', 'Irene', 'Mikkilineni', 'IMIKKILI', '650.124.1224', TO_DATE('1998-09-28 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2700', NULL, '120', '50');
INSERT INTO employees VALUES ('127', 'James', 'Landry', 'JLANDRY', '650.124.1334', TO_DATE('1999-01-14 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2400', NULL, '120', '50');
INSERT INTO employees VALUES ('128', 'Steven', 'Markle', 'SMARKLE', '650.124.1434', TO_DATE('2000-03-08 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2200', NULL, '120', '50');
INSERT INTO employees VALUES ('129', 'Laura', 'Bissot', 'LBISSOT', '650.124.5234', TO_DATE('1997-08-20 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3300', NULL, '121', '50');
INSERT INTO employees VALUES ('130', 'Mozhe', 'Atkinson', 'MATKINSO', '650.124.6234', TO_DATE('1997-10-30 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2800', NULL, '121', '50');
INSERT INTO employees VALUES ('131', 'James', 'Marlow', 'JAMRLOW', '650.124.7234', TO_DATE('1997-02-16 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2500', NULL, '121', '50');
INSERT INTO employees VALUES ('132', 'TJ', 'Olson', 'TJOLSON', '650.124.8234', TO_DATE('1999-04-10 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2100', NULL, '121', '50');
INSERT INTO employees VALUES ('133', 'Jason', 'Mallin', 'JMALLIN', '650.127.1934', TO_DATE('1996-06-14 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3300', NULL, '122', '50');
INSERT INTO employees VALUES ('134', 'Michael', 'Rogers', 'MROGERS', '650.127.1834', TO_DATE('1998-08-26 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2900', NULL, '122', '50');
INSERT INTO employees VALUES ('135', 'Ki', 'Gee', 'KGEE', '650.127.1734', TO_DATE('1999-12-12 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2400', NULL, '122', '50');
INSERT INTO employees VALUES ('136', 'Hazel', 'Philtanker', 'HPHILTAN', '650.127.1634', TO_DATE('2000-02-06 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2200', NULL, '122', '50');
INSERT INTO employees VALUES ('137', 'Renske', 'Ladwig', 'RLADWIG', '650.121.1234', TO_DATE('1995-07-14 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3600', NULL, '123', '50');
INSERT INTO employees VALUES ('138', 'Stephen', 'Stiles', 'SSTILES', '650.121.2034', TO_DATE('1997-10-26 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3200', NULL, '123', '50');
INSERT INTO employees VALUES ('139', 'John', 'Seo', 'JSEO', '650.121.2019', TO_DATE('1998-02-12 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2700', NULL, '123', '50');
INSERT INTO employees VALUES ('140', 'Joshua', 'Patel', 'JPATEL', '650.121.1834', TO_DATE('1998-04-06 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2500', NULL, '123', '50');
INSERT INTO employees VALUES ('141', 'Trenna', 'Rajs', 'TRAJS', '650.121.8009', TO_DATE('1995-10-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3500', NULL, '124', '50');
INSERT INTO employees VALUES ('142', 'Curtis', 'Davies', 'CDAVIES', '650.121.2994', TO_DATE('1997-01-29 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '3100', NULL, '124', '50');
INSERT INTO employees VALUES ('143', 'Randall', 'Matos', 'RMATOS', '650.121.2874', TO_DATE('1998-03-15 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2600', NULL, '124', '50');
INSERT INTO employees VALUES ('144', 'Peter', 'Vargas', 'PVARGAS', '650.121.2004', TO_DATE('1998-07-09 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'ST_CLERK', '2500', NULL, '124', '50');
INSERT INTO employees VALUES ('145', 'John', 'Russell', 'JRUSSEL', '011.44.1344.429268', TO_DATE('1996-10-01 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_MAN', '14000', '0.4', '100', '80');
INSERT INTO employees VALUES ('146', 'Karen', 'Partners', 'KPARTNER', '011.44.1344.467268', TO_DATE('1997-01-05 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_MAN', '13500', '0.3', '100', '80');
INSERT INTO employees VALUES ('147', 'Alberto', 'Errazuriz', 'AERRAZUR', '011.44.1344.429278', TO_DATE('1997-03-10 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_MAN', '12000', '0.3', '100', '80');
INSERT INTO employees VALUES ('148', 'Gerald', 'Cambrault', 'GCAMBRAU', '011.44.1344.619268', TO_DATE('1999-10-15 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_MAN', '11000', '0.3', '100', '80');
INSERT INTO employees VALUES ('149', 'Eleni', 'Zlotkey', 'EZLOTKEY', '011.44.1344.429018', TO_DATE('2000-01-29 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_MAN', '10500', '0.2', '100', '80');
INSERT INTO employees VALUES ('150', 'Peter', 'Tucker', 'PTUCKER', '011.44.1344.129268', TO_DATE('1997-01-30 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '10000', '0.3', '145', '80');
INSERT INTO employees VALUES ('151', 'David', 'Bernstein', 'DBERNSTE', '011.44.1344.345268', TO_DATE('1997-03-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '9500', '0.25', '145', '80');
INSERT INTO employees VALUES ('152', 'Peter', 'Hall', 'PHALL', '011.44.1344.478968', TO_DATE('1997-08-20 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '9000', '0.25', '145', '80');
INSERT INTO employees VALUES ('153', 'Christopher', 'Olsen', 'COLSEN', '011.44.1344.498718', TO_DATE('1998-03-30 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '8000', '0.2', '145', '80');
INSERT INTO employees VALUES ('154', 'Nanette', 'Cambrault', 'NCAMBRAU', '011.44.1344.987668', TO_DATE('1998-12-09 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7500', '0.2', '145', '80');
INSERT INTO employees VALUES ('155', 'Oliver', 'Tuvault', 'OTUVAULT', '011.44.1344.486508', TO_DATE('1999-11-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7000', '0.15', '145', '80');
INSERT INTO employees VALUES ('156', 'Janette', 'King', 'JKING', '011.44.1345.429268', TO_DATE('1996-01-30 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '10000', '0.35', '146', '80');
INSERT INTO employees VALUES ('157', 'Patrick', 'Sully', 'PSULLY', '011.44.1345.929268', TO_DATE('1996-03-04 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '9500', '0.35', '146', '80');
INSERT INTO employees VALUES ('158', 'Allan', 'McEwen', 'AMCEWEN', '011.44.1345.829268', TO_DATE('1996-08-01 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '9000', '0.35', '146', '80');
INSERT INTO employees VALUES ('159', 'Lindsey', 'Smith', 'LSMITH', '011.44.1345.729268', TO_DATE('1997-03-10 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '8000', '0.3', '146', '80');
INSERT INTO employees VALUES ('160', 'Louise', 'Doran', 'LDORAN', '011.44.1345.629268', TO_DATE('1997-12-15 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7500', '0.3', '146', '80');
INSERT INTO employees VALUES ('161', 'Sarath', 'Sewall', 'SSEWALL', '011.44.1345.529268', TO_DATE('1998-11-03 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7000', '0.25', '146', '80');
INSERT INTO employees VALUES ('162', 'Clara', 'Vishney', 'CVISHNEY', '011.44.1346.129268', TO_DATE('1997-11-11 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '10500', '0.25', '147', '80');
INSERT INTO employees VALUES ('163', 'Danielle', 'Greene', 'DGREENE', '011.44.1346.229268', TO_DATE('1999-03-19 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '9500', '0.15', '147', '80');
INSERT INTO employees VALUES ('164', 'Mattea', 'Marvins', 'MMARVINS', '011.44.1346.329268', TO_DATE('2000-01-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7200', '0.1', '147', '80');
INSERT INTO employees VALUES ('165', 'David', 'Lee', 'DLEE', '011.44.1346.529268', TO_DATE('2000-02-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '6800', '0.1', '147', '80');
INSERT INTO employees VALUES ('166', 'Sundar', 'Ande', 'SANDE', '011.44.1346.629268', TO_DATE('2000-03-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '6400', '0.1', '147', '80');
INSERT INTO employees VALUES ('167', 'Amit', 'Banda', 'ABANDA', '011.44.1346.729268', TO_DATE('2000-04-21 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '6200', '0.1', '147', '80');
INSERT INTO employees VALUES ('168', 'Lisa', 'Ozer', 'LOZER', '011.44.1343.929268', TO_DATE('1997-03-11 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '11500', '0.25', '148', '80');
INSERT INTO employees VALUES ('169', 'Harrison', 'Bloom', 'HBLOOM', '011.44.1343.829268', TO_DATE('1998-03-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '10000', '0.2', '148', '80');
INSERT INTO employees VALUES ('170', 'Tayler', 'Fox', 'TFOX', '011.44.1343.729268', TO_DATE('1998-01-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '9600', '0.2', '148', '80');
INSERT INTO employees VALUES ('171', 'William', 'Smith', 'WSMITH', '011.44.1343.629268', TO_DATE('1999-02-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7400', '0.15', '148', '80');
INSERT INTO employees VALUES ('172', 'Elizabeth', 'Bates', 'EBATES', '011.44.1343.529268', TO_DATE('1999-03-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7300', '0.15', '148', '80');
INSERT INTO employees VALUES ('173', 'Sundita', 'Kumar', 'SKUMAR', '011.44.1343.329268', TO_DATE('2000-04-21 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '6100', '0.1', '148', '80');
INSERT INTO employees VALUES ('174', 'Ellen', 'Abel', 'EABEL', '011.44.1644.429267', TO_DATE('1996-05-11 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '11000', '0.3', '149', '80');
INSERT INTO employees VALUES ('175', 'Alyssa', 'Hutton', 'AHUTTON', '011.44.1644.429266', TO_DATE('1997-03-19 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '8800', '0.25', '149', '80');
INSERT INTO employees VALUES ('176', 'Jonathon', 'Taylor', 'JTAYLOR', '011.44.1644.429265', TO_DATE('1998-03-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '8600', '0.2', '149', '80');
INSERT INTO employees VALUES ('177', 'Jack', 'Livingston', 'JLIVINGS', '011.44.1644.429264', TO_DATE('1998-04-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '8400', '0.2', '149', '80');
INSERT INTO employees VALUES ('178', 'Kimberely', 'Grant', 'KGRANT', '011.44.1644.429263', TO_DATE('1999-05-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '7000', '0.15', '149', NULL);
INSERT INTO employees VALUES ('179', 'Charles', 'Johnson', 'CJOHNSON', '011.44.1644.429262', TO_DATE('2000-01-04 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SA_REP', '6200', '0.1', '149', '80');
INSERT INTO employees VALUES ('180', 'Winston', 'Taylor', 'WTAYLOR', '650.507.9876', TO_DATE('1998-01-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3200', NULL, '120', '50');
INSERT INTO employees VALUES ('181', 'Jean', 'Fleaur', 'JFLEAUR', '650.507.9877', TO_DATE('1998-02-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3100', NULL, '120', '50');
INSERT INTO employees VALUES ('182', 'Martha', 'Sullivan', 'MSULLIVA', '650.507.9878', TO_DATE('1999-06-21 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2500', NULL, '120', '50');
INSERT INTO employees VALUES ('183', 'Girard', 'Geoni', 'GGEONI', '650.507.9879', TO_DATE('2000-02-03 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2800', NULL, '120', '50');
INSERT INTO employees VALUES ('184', 'Nandita', 'Sarchand', 'NSARCHAN', '650.509.1876', TO_DATE('1996-01-27 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '4200', NULL, '121', '50');
INSERT INTO employees VALUES ('185', 'Alexis', 'Bull', 'ABULL', '650.509.2876', TO_DATE('1997-02-20 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '4100', NULL, '121', '50');
INSERT INTO employees VALUES ('186', 'Julia', 'Dellinger', 'JDELLING', '650.509.3876', TO_DATE('1998-06-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3400', NULL, '121', '50');
INSERT INTO employees VALUES ('187', 'Anthony', 'Cabrio', 'ACABRIO', '650.509.4876', TO_DATE('1999-02-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3000', NULL, '121', '50');
INSERT INTO employees VALUES ('188', 'Kelly', 'Chung', 'KCHUNG', '650.505.1876', TO_DATE('1997-06-14 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3800', NULL, '122', '50');
INSERT INTO employees VALUES ('189', 'Jennifer', 'Dilly', 'JDILLY', '650.505.2876', TO_DATE('1997-08-13 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3600', NULL, '122', '50');
INSERT INTO employees VALUES ('190', 'Timothy', 'Gates', 'TGATES', '650.505.3876', TO_DATE('1998-07-11 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2900', NULL, '122', '50');
INSERT INTO employees VALUES ('191', 'Randall', 'Perkins', 'RPERKINS', '650.505.4876', TO_DATE('1999-12-19 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2500', NULL, '122', '50');
INSERT INTO employees VALUES ('192', 'Sarah', 'Bell', 'SBELL', '650.501.1876', TO_DATE('1996-02-04 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '4000', NULL, '123', '50');
INSERT INTO employees VALUES ('193', 'Britney', 'Everett', 'BEVERETT', '650.501.2876', TO_DATE('1997-03-03 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3900', NULL, '123', '50');
INSERT INTO employees VALUES ('194', 'Samuel', 'McCain', 'SMCCAIN', '650.501.3876', TO_DATE('1998-07-01 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3200', NULL, '123', '50');
INSERT INTO employees VALUES ('195', 'Vance', 'Jones', 'VJONES', '650.501.4876', TO_DATE('1999-03-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2800', NULL, '123', '50');
INSERT INTO employees VALUES ('196', 'Alana', 'Walsh', 'AWALSH', '650.507.9811', TO_DATE('1998-04-24 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3100', NULL, '124', '50');
INSERT INTO employees VALUES ('197', 'Kevin', 'Feeney', 'KFEENEY', '650.507.9822', TO_DATE('1998-05-23 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '3000', NULL, '124', '50');
INSERT INTO employees VALUES ('198', 'Donald', 'OConnell', 'DOCONNEL', '650.507.9833', TO_DATE('1999-06-21 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2600', NULL, '124', '50');
INSERT INTO employees VALUES ('199', 'Douglas', 'Grant', 'DGRANT', '650.507.9844', TO_DATE('2000-01-13 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'SH_CLERK', '2600', NULL, '124', '50');
INSERT INTO employees VALUES ('200', 'Jennifer', 'Whalen', 'JWHALEN', '515.123.4444', TO_DATE('1987-09-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'AD_ASST', '4400', NULL, '101', '10');
INSERT INTO employees VALUES ('201', 'Michael', 'Hartstein', 'MHARTSTE', '515.123.5555', TO_DATE('1996-02-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'MK_MAN', '13000', NULL, '100', '20');
INSERT INTO employees VALUES ('202', 'Pat', 'Fay', 'PFAY', '603.123.6666', TO_DATE('1997-08-17 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'MK_REP', '6000', NULL, '201', '20');
INSERT INTO employees VALUES ('203', 'Susan', 'Mavris', 'SMAVRIS', '515.123.7777', TO_DATE('1994-06-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'HR_REP', '6500', NULL, '101', '40');
INSERT INTO employees VALUES ('204', 'Hermann', 'Baer', 'HBAER', '515.123.8888', TO_DATE('1994-06-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'PR_REP', '10000', NULL, '101', '70');
INSERT INTO employees VALUES ('205', 'Shelley', 'Higgins', 'SHIGGINS', '515.123.8080', TO_DATE('1994-06-07 00:00:00', 'SYYYY-MM-DD HH24:MI:SS'), 'AC_MGR', '12000', NULL, '101', '110');
INSERT INTO employees VALUES ('206', 'William', 'Gietz', 'WGIETZ', '51
```

## 总结

Oracle 中自定义聚合函数采用的是面向对象的思想，将函数和变量都封装在 `type` 类型中。PostgreSQL 则需要我们定义一个类型并给出相应的函数来实现具体的功能，这些函数由于是全局的可能会导致函数名冲突，当然，我们可以通过 sechma 来避免这类问题的出现。PostgreSQL 中对于自定义函数还提供了许多其他的接口供用户使用，灵活性方面强于 Oracle。

## 参考

[1] https://docs.oracle.com/cd/B10501_01/appdev.920/a96595/dci11agg.htm
[2] https://www.postgresql.org/docs/13/sql-createaggregate.html
[3] https://www.postgresql.org/docs/13/xaggr.html#XAGGR-SUPPORT-FUNCTIONS

<div class="just-for-fun">
笑林广记 - 偷牛

有失牛而讼于官者，官问曰：“几时偷去的？”
答曰：“老爷，明日没有的。”
吏在旁不觉失笑。官怒曰：“想就是你偷了。”
吏洒两袖曰：“任凭老爷搜。”
</div>
