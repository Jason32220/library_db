CREATE DATABASE IF NOT EXISTS library_db;
USE library_db;

-- 建立 Reader 資料表
CREATE TABLE Reader (
  reader_id INT PRIMARY KEY,
  reader_name VARCHAR(50) NOT NULL,
  register_date DATE NOT NULL
);

-- 建立 Author 資料表
CREATE TABLE Author (
  author_id INT PRIMARY KEY,
  author_name VARCHAR(50) NOT NULL
);

-- 建立 Category 資料表
CREATE TABLE Category (
  category_id INT PRIMARY KEY,
  category_name VARCHAR(50) UNIQUE NOT NULL
);

SHOW ENGINE INNODB STATUS;

-- 建立 Book 資料表（直接管理可借狀態）
CREATE TABLE Book (
  book_id INT PRIMARY KEY,
  book_title VARCHAR(100) NOT NULL,
  author_id INT DEFAULT NULL,
  category_id INT DEFAULT NULL,
  publish_year INT,
  is_available BOOLEAN NOT NULL DEFAULT TRUE,
  FOREIGN KEY (author_id) REFERENCES Author(author_id) ON DELETE SET NULL,
  FOREIGN KEY (category_id) REFERENCES Category(category_id) ON DELETE SET NULL
);


-- 建立 BorrowRecord 資料表
CREATE TABLE BorrowRecord (
  borrow_id INT PRIMARY KEY,
  reader_id INT NOT NULL,
  book_id INT NOT NULL,
  borrow_date DATETIME NOT NULL,
  due_date DATETIME NOT NULL,
  return_date DATETIME,
  FOREIGN KEY (reader_id) REFERENCES Reader(reader_id) ON DELETE CASCADE,
  FOREIGN KEY (book_id) REFERENCES Book(book_id) ON DELETE CASCADE
);

-- 建立 Fine 資料表（罰款）
CREATE TABLE Fine (
  borrow_id INT PRIMARY KEY,
  amount DECIMAL(10,2) NOT NULL,
  is_paid BOOLEAN NOT NULL DEFAULT FALSE,
  FOREIGN KEY (borrow_id) REFERENCES BorrowRecord(borrow_id) ON DELETE CASCADE
);

-- 範例資料
INSERT INTO Category VALUES
(1, '武俠小說'), (2, '文學小說'), (3, '健康小說');

INSERT INTO Reader VALUES
(1, '王小明', '2023-01-10'),
(2, '林美麗', '2023-03-15'),
(3, '王大均', '2023-02-10');

INSERT INTO Author VALUES
(1, '金庸'), (2, '村上春樹'), (3, '梅子');

INSERT INTO Book VALUES
(1, '射鵰英雄傳', 1, 1, 1980, TRUE),
(2, '挪威的森林', 2, 2, 1995, TRUE),
(3, '金瓶梅', 3, 3, 1985, TRUE);

INSERT INTO BorrowRecord VALUES
(1, 1, 1, '2024-05-01 10:00:00', '2024-05-15 23:59:59', NULL),
(2, 2, 2, '2024-05-02 10:00:00', '2024-05-16 23:59:59', '2024-05-10 18:00:00');

INSERT INTO Fine VALUES
(1, 50.00, FALSE);

-- 建立熱門書籍視圖
CREATE VIEW HotBooks AS
SELECT B.book_id, B.book_title, COUNT(*) AS borrow_count
FROM BorrowRecord BR
JOIN Book B ON BR.book_id = B.book_id
GROUP BY B.book_id
HAVING COUNT(*) > 1;

-- 建立罰金計算函數
DELIMITER //
CREATE FUNCTION CalculateFine(due_date DATETIME, return_date DATETIME)
RETURNS INT DETERMINISTIC
BEGIN
  DECLARE days_late INT;
  IF return_date <= due_date THEN
    RETURN 0;
  ELSE
    SET days_late = DATEDIFF(return_date, due_date);
    RETURN days_late * 10;
  END IF;
END;
//
DELIMITER ;

-- 還書程序
DELIMITER //
CREATE PROCEDURE ReturnBook (
  IN borrowId INT,
  IN actual_return_date DATETIME
)
BEGIN
  DECLARE due_date DATETIME;
  DECLARE fine_amt INT;

  UPDATE BorrowRecord
  SET return_date = actual_return_date
  WHERE borrow_id = borrowId;

  SELECT due_date INTO due_date
  FROM BorrowRecord
  WHERE borrow_id = borrowId;

  SET fine_amt = CalculateFine(due_date, actual_return_date);

  IF fine_amt > 0 THEN
    INSERT INTO Fine (borrow_id, amount, is_paid)
    VALUES (borrowId, fine_amt, FALSE);
  END IF;
END;
//
DELIMITER ;

-- 還書後書籍設為可借
DELIMITER //
CREATE TRIGGER AfterReturnBook
AFTER UPDATE ON BorrowRecord
FOR EACH ROW
BEGIN
  IF NEW.return_date IS NOT NULL THEN
    UPDATE Book
    SET is_available = TRUE
    WHERE book_id = NEW.book_id;
  END IF;
END;
//
DELIMITER ;

-- 借書後書籍設為不可借
DELIMITER //
CREATE TRIGGER AfterBorrowBook
AFTER INSERT ON BorrowRecord
FOR EACH ROW
BEGIN
  UPDATE Book
  SET is_available = FALSE
  WHERE book_id = NEW.book_id;
END;
//
DELIMITER ;

--所有 「逾期未還書籍」 的借閱紀錄
SELECT * FROM BorrowRecord WHERE return_date IS NULL AND due_date < CURDATE();

--找出 借閱次數最多的前 5 本書
SELECT book_id, COUNT(*) AS borrow_count
FROM BorrowRecord
GROUP BY book_id
ORDER BY borrow_count DESC
LIMIT 5;
--查詢讀者（reader_id = 1）借過的所有書籍的名稱與借閱日期、歸還日期。
SELECT B.book_title, BR.borrow_date, BR.return_date
FROM BorrowRecord BR
JOIN Book B ON BR.book_id = B.book_id
WHERE BR.reader_id = 1;
--查詢每位讀者的姓名與他們總共借閱過幾本書
SELECT R.reader_name, (
    SELECT COUNT(*)
    FROM BorrowRecord BR
    WHERE BR.reader_id = R.reader_id
) AS total_borrowed
FROM Reader R;
-- 測試案例：借書記錄後是否將書籍設為不可借
INSERT INTO BorrowRecord (borrow_id, reader_id, book_id, borrow_date, due_date, return_date)
VALUES (6, 2, 2, '2024-06-01', '2024-06-15', NULL);

-- 查詢 Book 是否已更新 is_available 為 FALSE
SELECT * FROM Book WHERE book_id = 2;

-- 測試案例：歸還書籍並產生罰金（逾期）
CALL ReturnBook(6, '2025-06-20');

-- 查詢 BorrowRecord 是否已更新 return_date
SELECT * FROM BorrowRecord WHERE borrow_id = 5;

-- 查詢是否有產生對應的罰金紀錄
SELECT * FROM Fine WHERE borrow_id = 1;

-- 測試案例：歸還書籍後是否將書籍設為可借
SELECT * FROM Book WHERE book_id = 2;

-- 測試 Function：罰金計算函式
SELECT CalculateFine('2024-06-15', '2024-06-20') AS fine_amount;

-- 測試 View：HotBooks
SELECT * FROM HotBooks;

-- 測試子查詢：每位讀者的借書數量
SELECT R.reader_name, (
    SELECT COUNT(*)
    FROM BorrowRecord BR
    WHERE BR.reader_id = R.reader_id
) AS total_borrowed
FROM Reader R;

-- 測試權限（需以不同帳號執行）：
-- SELECT * FROM Book;  -- 使用 reader_user 帳號測試 SELECT 權限







